defmodule NostrSpamFighter.Jobs.RefreshBlocklistWorker do
  use Oban.Worker,
    queue: :blocklists,
    max_attempts: 3,
    unique: [
      period: 60,
      keys: [:blocklist_id],
      states: Oban.Job.unique_states(:incomplete)
    ]

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(15)

  import Ecto.Query
  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Policy.{Blocklist, BlocklistDownloader, Importer}

  def enqueue(blocklist_id, opts \\ []) do
    force? = Keyword.get(opts, :force, false)

    case Repo.get(Blocklist, blocklist_id) do
      nil ->
        {:error, :not_found}

      %Blocklist{enabled: false} ->
        {:error, :disabled}

      list ->
        if force? or not Blocklist.skip_auto_queue?(list) do
          insert_refresh(blocklist_id)
        else
          :ok
        end
    end
  end

  defp insert_refresh(blocklist_id) do
    result =
      %{blocklist_id: blocklist_id}
      |> new()
      |> Oban.insert()

    case result do
      {:ok, _job} ->
        mark_queued(blocklist_id)
        broadcast(blocklist_id)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def perform(%Oban.Job{args: %{"blocklist_id" => id}}) do
    if NostrSpamFighter.Memory.tight?() do
      {:snooze, 30}
    else
      do_perform(id)
    end
  end

  defp do_perform(id) do
    case Repo.get(Blocklist, id) do
      nil ->
        :ok

      %Blocklist{enabled: false} ->
        :ok

      %Blocklist{refresh_status: status} when status in ~w(failed rejected) ->
        :ok

      blocklist ->
        result = refresh(blocklist)
        broadcast(id)
        job_result(result)
    end
  end

  def refresh(%Blocklist{source_type: "manual"}), do: :ok

  def refresh(%Blocklist{source_type: "remote", source_url: url} = blocklist) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    demote_other_downloads(blocklist.id)

    {:ok, blocklist} =
      blocklist
      |> Blocklist.changeset(%{last_attempt_at: now, refresh_status: "downloading"})
      |> Repo.update()

    broadcast(blocklist.id)

    extra_headers =
      []
      |> maybe_put("if-none-match", blocklist.etag)
      |> maybe_put("if-modified-since", blocklist.last_modified)

    case BlocklistDownloader.get(url, extra_headers,
           on_progress: &broadcast_progress(blocklist.id, &1)
         ) do
      {:ok, :not_modified} ->
        mark_not_modified(blocklist, now)

      {:ok, %{body: body, etag: etag, last_modified: last_modified}} ->
        {:ok, blocklist} = mark_importing(blocklist)

        Importer.import_remote(blocklist, %{
          body: body,
          etag: etag,
          last_modified: last_modified,
          on_progress: &broadcast_progress(blocklist.id, &1)
        })

      {:error, message} ->
        Importer.record_failure(blocklist, message)
    end
  rescue
    exception ->
      Importer.record_failure(blocklist, Exception.message(exception))
  catch
    :exit, reason ->
      Importer.record_failure(blocklist, Exception.format_exit(reason))
  end

  def handle_telemetry([:oban, :job, :exception], _measurements, %{job: job} = meta, _config) do
    if job.worker == inspect(__MODULE__) do
      record_job_exception(job, meta)
    end

    :ok
  end

  def record_job_exception(%Oban.Job{args: %{"blocklist_id" => id}}, meta) do
    case Repo.get(Blocklist, id) do
      %Blocklist{refresh_status: status} = list when status in ~w(queued downloading importing) ->
        Importer.record_failure(list, exception_message(meta))
        broadcast(id)
        :ok

      _ ->
        :ok
    end
  end

  # Import failures are already stored on the list. Retrying would
  # re-download a file we already have.
  defp job_result({:error, {:import_failed, _}}), do: :ok
  defp job_result(result), do: result

  defp mark_importing(blocklist) do
    {:ok, updated} =
      blocklist
      |> Blocklist.changeset(%{refresh_status: "importing"})
      |> Repo.update()

    broadcast(updated.id)
    {:ok, updated}
  end

  defp mark_queued(blocklist_id) do
    from(b in Blocklist, where: b.id == ^blocklist_id)
    |> Repo.update_all(set: [refresh_status: "queued"])
  end

  defp demote_other_downloads(current_id) do
    from(b in Blocklist,
      where: b.refresh_status in ^["downloading", "importing"],
      where: b.id != ^current_id
    )
    |> Repo.update_all(set: [refresh_status: "queued"])
  end

  defp maybe_put(headers, _name, nil), do: headers
  defp maybe_put(headers, name, value), do: [{name, value} | headers]

  defp mark_not_modified(blocklist, now) do
    blocklist
    |> Blocklist.changeset(%{
      last_success_at: now,
      last_attempt_at: now,
      last_error: nil,
      refresh_status: "ok",
      next_refresh_at: DateTime.add(now, blocklist.refresh_interval_s, :second)
    })
    |> Repo.update()

    :ok
  end

  defp broadcast(id) do
    Phoenix.PubSub.broadcast(
      NostrSpamFighter.PubSub,
      "blocklists",
      {:blocklist_refreshed, id}
    )
  end

  defp exception_message(%{reason: %Oban.TimeoutError{}}) do
    "timed out after 15 minutes"
  end

  defp exception_message(%{reason: reason}) when is_exception(reason) do
    Exception.message(reason)
  end

  defp exception_message(%{reason: reason}) when is_binary(reason), do: reason
  defp exception_message(%{reason: reason}), do: inspect(reason)
  defp exception_message(_), do: "refresh failed"

  defp broadcast_progress(id, progress) do
    Phoenix.PubSub.broadcast(
      NostrSpamFighter.PubSub,
      "blocklists",
      {:blocklist_download_progress, id, progress}
    )
  end
end
