defmodule NostrSpamFighter.Policy do
  @moduledoc """
  Category and blocklist administration.
  """

  import Ecto.Query
  alias NostrSpamFighter.Repo

  alias NostrSpamFighter.Policy.{
    Blocklist,
    BlocklistEntry,
    BlocklistVersion,
    Cache,
    Category,
    Importer
  }

  alias NostrSpamFighter.Moderation.Match

  @default_categories [
    %{
      slug: "adult",
      name: "Adult",
      description: "Adult sexual content",
      enabled: true,
      blocks_serving: true
    },
    %{
      slug: "malware",
      name: "Malware",
      description: "Malware and exploit distribution",
      enabled: true,
      blocks_serving: true
    },
    %{
      slug: "scam",
      name: "Scam",
      description: "Fraud and phishing",
      enabled: true,
      blocks_serving: true
    },
    %{
      slug: "spam",
      name: "Spam",
      description: "Unsolicited or deceptive promotion",
      enabled: true,
      blocks_serving: false
    }
  ]

  def default_categories, do: @default_categories

  def list_categories, do: Repo.all(from c in Category, order_by: c.slug)
  def get_category!(id), do: Repo.get!(Category, id)

  def ensure_default_categories do
    Enum.each(@default_categories, fn attrs ->
      %Category{}
      |> Category.changeset(attrs)
      |> Repo.insert(on_conflict: :nothing, conflict_target: :slug)
    end)

    list_categories()
  end

  def create_category(attrs) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
    |> maybe_rebuild()
  end

  def update_category(%Category{} = category, attrs) do
    changeset =
      if public_labels_exist?(category) do
        Category.slug_locked_changeset(category, attrs)
      else
        Category.changeset(category, attrs)
      end

    changeset
    |> Repo.update()
    |> maybe_rebuild()
  end

  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end

  def list_blocklists do
    Repo.all(from b in Blocklist, preload: [:category, :active_version], order_by: b.name)
    |> with_runtime_refresh_status()
  end

  def get_blocklist!(id) do
    Blocklist
    |> Repo.get!(id)
    |> Repo.preload([:category, :active_version, :versions])
  end

  def get_blocklist_for_ui!(id) do
    id
    |> get_blocklist!()
    |> with_runtime_refresh_status()
  end

  @doc """
  Downloading is only true while an Oban job is actually executing.
  Leftover rows from a crash or an old parallel run are shown as queued.
  """
  def with_runtime_refresh_status(lists_or_list, opts \\ [])

  def with_runtime_refresh_status(%Blocklist{} = list, opts) do
    hd(with_runtime_refresh_status([list], opts))
  end

  def with_runtime_refresh_status(lists, opts) when is_list(lists) do
    active_id =
      opts
      |> Keyword.get(:executing_ids, executing_refresh_ids())
      |> List.wrap()
      |> Enum.take(1)
      |> List.first()

    Enum.map(lists, fn list ->
      executing? = active_id && to_string(list.id) == to_string(active_id)

      cond do
        # Worker writes ok/failed before Oban flips the job off executing.
        # Do not promote a finished list back to downloading.
        list.refresh_status in ~w(ok failed rejected) ->
          list

        list.refresh_status == "importing" and executing? ->
          list

        executing? ->
          %{list | refresh_status: "downloading"}

        list.refresh_status in ~w(downloading importing) ->
          stale_refresh_status(list)

        true ->
          list
      end
    end)
  end

  @doc """
  After a restart, leftover Oban rows can stay `executing` until Lifeline
  rescues them (30 minutes) and occupy the single blocklists slot.

  Deleting them (instead of flipping to `available`) lets a later insert
  notify Oban so the queue actually starts again.
  """
  def recover_orphaned_refresh_jobs do
    states = Enum.map(Oban.Job.unique_states(:incomplete), &to_string/1)

    jobs =
      Repo.all(
        from j in Oban.Job,
          where: j.queue == "blocklists",
          where: j.state in ^states
      )

    refresh_ids =
      for %{
            worker: "NostrSpamFighter.Jobs.RefreshBlocklistWorker",
            args: %{"blocklist_id" => id}
          } <- jobs,
          do: id

    if jobs != [] do
      from(j in Oban.Job, where: j.id in ^Enum.map(jobs, & &1.id))
      |> Repo.delete_all()
    end

    refresh_ids
  end

  defp executing_refresh_ids do
    worker = inspect(NostrSpamFighter.Jobs.RefreshBlocklistWorker)

    from(j in Oban.Job,
      where: j.worker == ^worker,
      where: j.state == "executing",
      order_by: [desc: j.attempted_at],
      limit: 1,
      select: j.args
    )
    |> Repo.one()
    |> case do
      %{"blocklist_id" => id} when is_binary(id) -> [id]
      _ -> []
    end
  end

  def create_blocklist(attrs) do
    %Blocklist{}
    |> Blocklist.changeset(attrs)
    |> Repo.insert()
    |> maybe_enqueue_refresh()
    |> maybe_rebuild()
  end

  def update_blocklist(%Blocklist{} = blocklist, attrs) do
    blocklist
    |> Blocklist.changeset(attrs)
    |> Repo.update()
    |> maybe_rebuild()
  end

  def change_blocklist(%Blocklist{} = blocklist, attrs \\ %{}) do
    Blocklist.changeset(blocklist, attrs)
  end

  def delete_blocklist(%Blocklist{} = blocklist) do
    result =
      Repo.transaction(fn ->
        Repo.delete_all(from m in Match, where: m.blocklist_id == ^blocklist.id)

        case Repo.delete(blocklist) do
          {:ok, deleted} -> deleted
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    maybe_rebuild(result)
  end

  def import_manual_entries(%Blocklist{} = blocklist, body) do
    Importer.import_manual(blocklist, body)
  end

  def list_versions(%Blocklist{} = blocklist) do
    Repo.all(
      from v in BlocklistVersion,
        where: v.blocklist_id == ^blocklist.id,
        order_by: [desc: v.inserted_at]
    )
  end

  def list_entries(%BlocklistVersion{} = version, limit \\ 200) do
    Repo.all(
      from e in BlocklistEntry,
        where: e.blocklist_version_id == ^version.id,
        limit: ^limit,
        order_by: e.normalized_value
    )
  end

  def public_labels_exist?(%Category{id: id}) do
    Repo.exists?(
      from l in NostrSpamFighter.Moderation.PublishedLabel,
        where: l.category_id == ^id
    )
  end

  def restart_blocklist_refreshes do
    orphan_ids = recover_orphaned_refresh_jobs()
    reset_incomplete_refreshes()
    requeue_refresh_ids(orphan_ids)
    :ok
  end

  @doc """
  Clears leftover queued/downloading rows after a crash or restart, then
  re-enqueues enabled remote lists so the fetch can run again.
  """
  def reset_incomplete_refreshes(opts \\ []) do
    enqueue? = Keyword.get(opts, :enqueue, true)

    incomplete =
      Repo.all(
        from b in Blocklist,
          where: b.refresh_status in ^["queued", "downloading", "importing"]
      )

    Enum.each(incomplete, fn blocklist ->
      blocklist
      |> Blocklist.changeset(%{refresh_status: completed_refresh_status(blocklist)})
      |> Repo.update!()
    end)

    if enqueue? do
      incomplete
      |> Enum.filter(&(&1.enabled and &1.source_type == "remote"))
      |> Enum.reject(&Blocklist.skip_auto_queue?/1)
      |> Enum.each(&NostrSpamFighter.Jobs.RefreshBlocklistWorker.enqueue(&1.id))
    end

    length(incomplete)
  end

  defp stale_refresh_status(%Blocklist{last_error: error} = list) when is_binary(error) do
    %{list | refresh_status: completed_refresh_status(list)}
  end

  defp stale_refresh_status(list) do
    %{list | refresh_status: "failed", last_error: "refresh was interrupted"}
  end

  defp completed_refresh_status(%Blocklist{last_error: error}) when is_binary(error) do
    if Importer.permanent_failure?(error), do: "rejected", else: "failed"
  end

  defp completed_refresh_status(%Blocklist{last_success_at: %DateTime{}}), do: "ok"
  defp completed_refresh_status(_), do: "idle"

  defp requeue_refresh_ids(ids) do
    ids = ids |> Enum.uniq() |> Enum.reject(&is_nil/1)

    if ids != [] do
      Repo.all(
        from b in Blocklist,
          where: b.id in ^ids,
          where: b.enabled == true,
          where: b.source_type == "remote",
          where: b.refresh_status not in ^["failed", "rejected"],
          where: is_nil(b.last_error)
      )
      |> Enum.each(&NostrSpamFighter.Jobs.RefreshBlocklistWorker.enqueue(&1.id))
    end
  end

  defp maybe_enqueue_refresh({:ok, %Blocklist{source_type: "remote"} = blocklist}) do
    NostrSpamFighter.Jobs.RefreshBlocklistWorker.enqueue(blocklist.id)
    {:ok, get_blocklist!(blocklist.id)}
  end

  defp maybe_enqueue_refresh(result), do: result

  defp maybe_rebuild({:ok, record}) do
    Cache.rebuild()
    {:ok, record}
  end

  defp maybe_rebuild(error), do: error
end
