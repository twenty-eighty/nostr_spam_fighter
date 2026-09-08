defmodule NostrSpamFighter.OpsTest do
  use NostrSpamFighter.DataCase, async: false

  import Ecto.Query
  alias NostrSpamFighter.Ops
  alias NostrSpamFighter.Jobs.ScanEventWorker
  alias NostrSpamFighter.Nostr.IngestQueue

  test "snapshot is idle when nothing is running" do
    snapshot = Ops.snapshot()
    assert snapshot.items == []
    assert snapshot.queued.total == 0
    assert snapshot.queued_label == nil
  end

  test "ingest queue status is available" do
    assert %{queued: 0, inflight: 0} = IngestQueue.status()
  end

  test "snapshot lists an executing scan" do
    event_id = String.duplicate("cd", 32)

    {:ok, job} =
      %{event_id: event_id}
      |> ScanEventWorker.new()
      |> Oban.insert()

    from(j in Oban.Job, where: j.id == ^job.id)
    |> Repo.update_all(set: [state: "executing"])

    snapshot = Ops.snapshot()
    item = Enum.find(snapshot.items, &(&1.id == "job-#{job.id}"))
    assert item.kind == :scan
    assert item.title =~ "Scanning"
    assert item.event_id == event_id
  end

  test "snapshot includes import progress on a blocklist job" do
    {:ok, category} =
      NostrSpamFighter.Policy.create_category(%{
        slug: "ops-test",
        name: "Ops test",
        enabled: true,
        blocks_serving: true
      })

    {:ok, list} =
      NostrSpamFighter.Policy.create_blocklist(%{
        name: "malware-nl",
        category_id: category.id,
        source_type: "remote",
        source_url: "https://example.com/malware-nl.txt",
        format: "domains"
      })

    {:ok, _} =
      list
      |> NostrSpamFighter.Policy.Blocklist.changeset(%{refresh_status: "importing"})
      |> Repo.update()

    {:ok, job} =
      %{blocklist_id: list.id}
      |> NostrSpamFighter.Jobs.RefreshBlocklistWorker.new()
      |> Oban.insert()

    from(j in Oban.Job, where: j.id == ^job.id)
    |> Repo.update_all(set: [state: "executing"])

    snapshot =
      Ops.snapshot(
        progress: %{
          list.id => %{
            phase: "import",
            stage: "saving",
            done: 400_000,
            total: 2_656_393,
            percent: 15.1
          }
        }
      )

    item = Enum.find(snapshot.items, &(&1.id == "job-#{job.id}"))
    assert item.title == "Importing malware-nl"
    assert item.detail == "Saving 400K / 2.7M"
    assert item.blocklist_id == list.id
  end
end
