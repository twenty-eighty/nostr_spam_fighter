defmodule NostrSpamFighter.Jobs.ScheduleBlocklistRefreshWorkerTest do
  use NostrSpamFighter.DataCase, async: false
  use Oban.Testing, repo: NostrSpamFighter.Repo

  alias NostrSpamFighter.Policy
  alias NostrSpamFighter.Policy.Blocklist
  alias NostrSpamFighter.Jobs.{RefreshBlocklistWorker, ScheduleBlocklistRefreshWorker}

  test "skips failed and rejected lists even when forcing a refresh" do
    [adult | _] = Policy.ensure_default_categories()

    {:ok, rejected} =
      Policy.create_blocklist(%{
        name: "Too big",
        category_id: adult.id,
        source_type: "remote",
        source_url: "https://example.com/huge.txt",
        format: "domains"
      })

    {:ok, rejected} =
      rejected
      |> Blocklist.changeset(%{
        refresh_status: "rejected",
        last_error: "download too large (72.4 MB, limit 70 MB)"
      })
      |> NostrSpamFighter.Repo.update()

    {:ok, failed} =
      Policy.create_blocklist(%{
        name: "Import error",
        category_id: adult.id,
        source_type: "remote",
        source_url: "https://example.com/broken.txt",
        format: "domains"
      })

    {:ok, _failed} =
      failed
      |> Blocklist.changeset(%{
        refresh_status: "failed",
        last_error: "HTTP 404 Not Found"
      })
      |> NostrSpamFighter.Repo.update()

    {:ok, ok} =
      Policy.create_blocklist(%{
        name: "Normal",
        category_id: adult.id,
        source_type: "remote",
        source_url: "https://example.com/normal.txt",
        format: "domains"
      })

    NostrSpamFighter.Repo.delete_all(Oban.Job)

    assert ScheduleBlocklistRefreshWorker.enqueue_due(force: true) == 1
    refute_enqueued(worker: RefreshBlocklistWorker, args: %{blocklist_id: rejected.id})
    refute_enqueued(worker: RefreshBlocklistWorker, args: %{blocklist_id: failed.id})
    assert_enqueued(worker: RefreshBlocklistWorker, args: %{blocklist_id: ok.id})
  end
end
