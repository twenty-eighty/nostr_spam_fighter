defmodule NostrSpamFighter.Ops do
  @moduledoc """
  Live snapshot of what the server is doing right now.
  """

  import Ecto.Query
  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Nostr.{IngestQueue, RelayIngest}
  alias NostrSpamFighter.Policy.{Blocklist, Importer}
  alias NostrSpamFighter.Relays

  def snapshot(opts \\ []) do
    progress = Keyword.get(opts, :progress, %{})
    ingest = ingest_snapshot()
    jobs = executing_jobs()
    queued = queued_job_counts()
    items = ingest_items(ingest) ++ Enum.map(jobs, &job_item(&1, progress))

    %{
      ingest: ingest,
      items: items,
      queued: queued,
      queued_label: queued_label(queued)
    }
  end

  defp ingest_snapshot do
    status = RelayIngest.status()
    queue = IngestQueue.status()

    Map.merge(status, queue)
    |> Map.put(:relay_count, length(Relays.list_read_urls()))
  end

  defp ingest_items(%{pending: true}) do
    [
      %{
        id: "ingest",
        kind: :ingest,
        title: "Starting relay ingest",
        detail: "Connecting in a few seconds",
        event_id: nil,
        blocklist_id: nil
      }
    ]
  end

  defp ingest_items(%{running: true} = ingest) do
    [
      %{
        id: "ingest",
        kind: :ingest,
        title: ingest_title(ingest),
        detail: ingest_detail(ingest),
        event_id: nil,
        blocklist_id: nil
      }
    ]
  end

  defp ingest_items(%{queued: queued, inflight: inflight})
       when queued > 0 or inflight > 0 do
    [
      %{
        id: "ingest",
        kind: :ingest,
        title: "Ingesting events",
        detail: ingest_queue_detail(%{queued: queued, inflight: inflight}),
        event_id: nil,
        blocklist_id: nil
      }
    ]
  end

  defp ingest_items(_), do: []

  defp ingest_title(%{relay_count: 1}), do: "Listening on 1 relay"
  defp ingest_title(%{relay_count: count}), do: "Listening on #{count} relays"

  defp ingest_detail(ingest) do
    case ingest_queue_detail(ingest) do
      nil -> "Waiting for kind 30023 articles"
      detail -> detail
    end
  end

  defp ingest_queue_detail(%{queued: 0, inflight: 0}), do: nil

  defp ingest_queue_detail(%{queued: queued, inflight: inflight}) do
    [
      count_phrase(inflight, "event being stored", "events being stored"),
      count_phrase(queued, "waiting", "waiting")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp executing_jobs do
    from(j in Oban.Job,
      where: j.state == "executing",
      order_by: [desc: j.attempted_at],
      limit: 12
    )
    |> Repo.all()
  end

  defp queued_job_counts do
    counts =
      from(j in Oban.Job,
        where: j.state in ^["available", "scheduled", "retryable"],
        group_by: j.queue,
        select: {j.queue, count(j.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      by_queue: counts,
      total: counts |> Map.values() |> Enum.sum()
    }
  end

  defp queued_label(%{total: 0}), do: nil

  defp queued_label(%{by_queue: counts}) do
    counts
    |> Enum.sort_by(fn {queue, _} -> queue end)
    |> Enum.map(fn {queue, n} -> "#{n} #{queue_waiting_label(queue, n)}" end)
    |> Enum.join(" · ")
  end

  defp queue_waiting_label("scans", 1), do: "scan waiting"
  defp queue_waiting_label("scans", _), do: "scans waiting"
  defp queue_waiting_label("blocklists", 1), do: "blocklist refresh waiting"
  defp queue_waiting_label("blocklists", _), do: "blocklist refreshes waiting"
  defp queue_waiting_label("nostr_publish", 1), do: "label publish waiting"
  defp queue_waiting_label("nostr_publish", _), do: "label publishes waiting"
  defp queue_waiting_label("maintenance", 1), do: "maintenance job waiting"
  defp queue_waiting_label("maintenance", _), do: "maintenance jobs waiting"
  defp queue_waiting_label("network", 1), do: "network job waiting"
  defp queue_waiting_label("network", _), do: "network jobs waiting"
  defp queue_waiting_label(queue, 1), do: "#{queue} job waiting"
  defp queue_waiting_label(queue, _), do: "#{queue} jobs waiting"

  defp job_item(%Oban.Job{} = job, progress) do
    {kind, title, detail, event_id, blocklist_id} = describe_job(job, progress)

    %{
      id: "job-#{job.id}",
      kind: kind,
      title: title,
      detail: detail,
      event_id: event_id,
      blocklist_id: blocklist_id
    }
  end

  defp describe_job(%Oban.Job{worker: worker, args: args, queue: queue} = job, progress) do
    case worker do
      "NostrSpamFighter.Jobs.ScanEventWorker" ->
        event_id = args["event_id"]
        {:scan, "Scanning #{short_id(event_id)}", queue, event_id, nil}

      "NostrSpamFighter.Jobs.RefreshBlocklistWorker" ->
        describe_blocklist_job(args["blocklist_id"], progress)

      "NostrSpamFighter.Jobs.ScheduleBlocklistRefreshWorker" ->
        {:blocklist, "Scheduling due blocklist refreshes", queue, nil, nil}

      "NostrSpamFighter.Jobs.PublishLabelWorker" ->
        event_id = args["event_id"]
        {:publish, "Publishing label for #{short_id(event_id)}", queue, event_id, nil}

      "NostrSpamFighter.Jobs.WithdrawLabelWorker" ->
        event_id = args["event_id"]
        {:withdraw, "Withdrawing label for #{short_id(event_id)}", queue, event_id, nil}

      "NostrSpamFighter.Jobs.RescanEventsWorker" ->
        {:rescan, "Queuing event rescans", queue, nil, nil}

      _ ->
        {:job, worker_name(worker), "#{queue} · attempt #{job.attempt}", nil, nil}
    end
  end

  defp describe_blocklist_job(blocklist_id, progress) do
    list = blocklist_id && Repo.get(Blocklist, blocklist_id)
    name = (list && list.name) || "blocklist"

    title =
      case list && list.refresh_status do
        "downloading" -> "Downloading #{name}"
        "importing" -> "Importing #{name}"
        _ -> "Refreshing #{name}"
      end

    detail =
      progress_detail(progress_for(progress, blocklist_id)) ||
        (list && list.refresh_status) ||
        "blocklists"

    {:blocklist, title, detail, nil, list && list.id}
  end

  defp progress_for(_progress, nil), do: nil

  defp progress_for(progress, id) do
    Map.get(progress, id) || Map.get(progress, to_string(id))
  end

  defp progress_detail(%{phase: "import", stage: stage, done: done, total: total})
       when is_integer(total) and total > 0 do
    "#{import_stage(stage)} #{Importer.format_count(done)} / #{Importer.format_count(total)}"
  end

  defp progress_detail(%{bytes: bytes, total: total})
       when is_integer(bytes) and is_integer(total) and total > 0 do
    "#{Importer.format_bytes(bytes)} / #{Importer.format_bytes(total)}"
  end

  defp progress_detail(%{bytes: bytes}) when is_integer(bytes) do
    Importer.format_bytes(bytes)
  end

  defp progress_detail(_), do: nil

  defp import_stage("parsing"), do: "Parsing"
  defp import_stage("saving"), do: "Saving"
  defp import_stage(_), do: "Importing"

  defp short_id(id) when is_binary(id) and byte_size(id) > 12, do: String.slice(id, 0, 12)
  defp short_id(id) when is_binary(id), do: id
  defp short_id(_), do: "event"

  defp worker_name(worker) when is_binary(worker) do
    worker
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
    |> String.replace("_", " ")
  end

  defp worker_name(_), do: "background job"

  defp count_phrase(0, _one, _many), do: nil
  defp count_phrase(1, one, _many), do: "1 #{one}"
  defp count_phrase(n, _one, many), do: "#{n} #{many}"
end
