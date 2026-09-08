defmodule NostrSpamFighter.PolicyTest do
  use NostrSpamFighter.DataCase, async: false
  use Oban.Testing, repo: NostrSpamFighter.Repo

  alias NostrSpamFighter.Policy
  alias NostrSpamFighter.Jobs.RefreshBlocklistWorker

  test "ensure_default_categories inserts once" do
    first = Policy.ensure_default_categories()
    slugs = Enum.map(first, & &1.slug)
    assert "adult" in slugs
    assert "malware" in slugs
    assert "scam" in slugs
    assert "spam" in slugs

    second = Policy.ensure_default_categories()
    assert Enum.map(second, & &1.id) == Enum.map(first, & &1.id)
  end

  test "blocklists are unique per category name and can be deleted" do
    [adult | _] = Policy.ensure_default_categories()

    attrs = %{
      name: "Adult hosts",
      category_id: adult.id,
      source_type: "manual",
      format: "domains"
    }

    assert {:ok, list} = Policy.create_blocklist(attrs)
    assert {:error, changeset} = Policy.create_blocklist(attrs)
    assert changeset.errors[:name]

    assert {:ok, _} = Policy.delete_blocklist(list)
    assert Policy.list_blocklists() == []
    assert {:ok, _} = Policy.create_blocklist(attrs)
  end

  test "creating a remote blocklist enqueues a fetch" do
    [adult | _] = Policy.ensure_default_categories()

    assert {:ok, list} =
             Policy.create_blocklist(%{
               name: "Remote abuse",
               category_id: adult.id,
               source_type: "remote",
               source_url: "https://example.com/abuse.txt",
               format: "domains"
             })

    assert_enqueued(worker: RefreshBlocklistWorker, args: %{blocklist_id: list.id})
    assert list.refresh_status == "queued"
  end

  test "reset_incomplete_refreshes clears stuck downloads and re-enqueues them" do
    [adult | _] = Policy.ensure_default_categories()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, downloading} =
      Policy.create_blocklist(%{
        name: "Stuck download",
        category_id: adult.id,
        source_type: "remote",
        source_url: "https://example.com/stuck.txt",
        format: "domains"
      })

    {:ok, downloading} =
      downloading
      |> NostrSpamFighter.Policy.Blocklist.changeset(%{
        refresh_status: "downloading",
        last_error: "timed out after 120s waiting for the server",
        last_attempt_at: now
      })
      |> NostrSpamFighter.Repo.update()

    {:ok, never_started} =
      Policy.create_blocklist(%{
        name: "Never started",
        category_id: adult.id,
        source_type: "remote",
        source_url: "https://example.com/never.txt",
        format: "domains"
      })

    {:ok, _never_started} =
      never_started
      |> NostrSpamFighter.Policy.Blocklist.changeset(%{refresh_status: "queued"})
      |> NostrSpamFighter.Repo.update()

    assert Policy.reset_incomplete_refreshes(enqueue: false) == 2
    assert Policy.get_blocklist!(downloading.id).refresh_status == "failed"
    assert Policy.get_blocklist!(never_started.id).refresh_status == "idle"
    refute NostrSpamFighter.Policy.Blocklist.refreshing?(Policy.get_blocklist!(downloading.id))

    stuck = Policy.get_blocklist!(downloading.id)

    {:ok, _} =
      stuck
      |> NostrSpamFighter.Policy.Blocklist.changeset(%{refresh_status: "downloading"})
      |> NostrSpamFighter.Repo.update()

    NostrSpamFighter.Repo.delete_all(Oban.Job)
    assert Policy.reset_incomplete_refreshes() == 1
    assert Policy.get_blocklist!(downloading.id).refresh_status == "failed"
    refute_enqueued(worker: RefreshBlocklistWorker, args: %{blocklist_id: downloading.id})

    {:ok, interrupted} =
      Policy.create_blocklist(%{
        name: "Interrupted clean",
        category_id: adult.id,
        source_type: "remote",
        source_url: "https://example.com/interrupted.txt",
        format: "domains"
      })

    {:ok, _} =
      interrupted
      |> NostrSpamFighter.Policy.Blocklist.changeset(%{
        refresh_status: "downloading",
        last_error: nil
      })
      |> NostrSpamFighter.Repo.update()

    NostrSpamFighter.Repo.delete_all(Oban.Job)
    assert Policy.reset_incomplete_refreshes() == 1
    assert Policy.get_blocklist!(interrupted.id).refresh_status == "queued"
    assert_enqueued(worker: RefreshBlocklistWorker, args: %{blocklist_id: interrupted.id})
  end

  test "stale downloading rows are shown as queued unless a job is executing" do
    [adult | _] = Policy.ensure_default_categories()

    {:ok, list} =
      Policy.create_blocklist(%{
        name: "Stale download",
        category_id: adult.id,
        source_type: "remote",
        source_url: "https://example.com/stale.txt",
        format: "domains"
      })

    {:ok, list} =
      list
      |> NostrSpamFighter.Policy.Blocklist.changeset(%{refresh_status: "downloading"})
      |> NostrSpamFighter.Repo.update()

    [shown] = Policy.with_runtime_refresh_status([list], executing_ids: [])
    assert shown.refresh_status == "failed"
    assert shown.last_error == "refresh was interrupted"

    [active] = Policy.with_runtime_refresh_status([list], executing_ids: [list.id])
    assert active.refresh_status == "downloading"

    {:ok, other} =
      Policy.create_blocklist(%{
        name: "Also stale",
        category_id: adult.id,
        source_type: "remote",
        source_url: "https://example.com/also-stale.txt",
        format: "domains"
      })

    {:ok, other} =
      other
      |> NostrSpamFighter.Policy.Blocklist.changeset(%{refresh_status: "downloading"})
      |> NostrSpamFighter.Repo.update()

    shown =
      Policy.with_runtime_refresh_status([list, other], executing_ids: [list.id, other.id])

    statuses = Map.new(shown, &{&1.id, &1.refresh_status})
    assert statuses[list.id] == "downloading"
    assert statuses[other.id] == "failed"
    assert Enum.count(shown, &(&1.refresh_status == "downloading")) == 1
  end

  test "recover deletes leftover blocklist jobs instead of leaving them available" do
    [adult | _] = Policy.ensure_default_categories()

    {:ok, list} =
      Policy.create_blocklist(%{
        name: "Orphaned fetch",
        category_id: adult.id,
        source_type: "remote",
        source_url: "https://example.com/orphan.txt",
        format: "domains"
      })

    job =
      NostrSpamFighter.Repo.one!(
        from j in Oban.Job,
          where: j.worker == "NostrSpamFighter.Jobs.RefreshBlocklistWorker",
          where: fragment("? ->> 'blocklist_id' = ?", j.args, ^list.id)
      )

    from(j in Oban.Job, where: j.id == ^job.id)
    |> NostrSpamFighter.Repo.update_all(set: [state: "executing"])

    assert list.id in Policy.recover_orphaned_refresh_jobs()
    refute NostrSpamFighter.Repo.get(Oban.Job, job.id)
  end

  test "finished refresh status is not promoted back to downloading" do
    [adult | _] = Policy.ensure_default_categories()

    {:ok, list} =
      Policy.create_blocklist(%{
        name: "Just finished",
        category_id: adult.id,
        source_type: "remote",
        source_url: "https://example.com/done.txt",
        format: "domains"
      })

    {:ok, list} =
      list
      |> NostrSpamFighter.Policy.Blocklist.changeset(%{refresh_status: "ok"})
      |> NostrSpamFighter.Repo.update()

    [shown] = Policy.with_runtime_refresh_status([list], executing_ids: [list.id])
    assert shown.refresh_status == "ok"
  end

  test "importing stays importing while a job is executing" do
    [adult | _] = Policy.ensure_default_categories()

    {:ok, list} =
      Policy.create_blocklist(%{
        name: "Importing list",
        category_id: adult.id,
        source_type: "remote",
        source_url: "https://example.com/importing.txt",
        format: "domains"
      })

    {:ok, list} =
      list
      |> NostrSpamFighter.Policy.Blocklist.changeset(%{refresh_status: "importing"})
      |> NostrSpamFighter.Repo.update()

    [shown] = Policy.with_runtime_refresh_status([list], executing_ids: [list.id])
    assert shown.refresh_status == "importing"

    [stale] = Policy.with_runtime_refresh_status([list], executing_ids: [])
    assert stale.refresh_status == "failed"
    assert stale.last_error == "refresh was interrupted"
  end

  test "stale importing with a stored error is shown as failed" do
    [adult | _] = Policy.ensure_default_categories()

    {:ok, list} =
      Policy.create_blocklist(%{
        name: "Failed import",
        category_id: adult.id,
        source_type: "remote",
        source_url: "https://example.com/failed-import.txt",
        format: "domains"
      })

    {:ok, list} =
      list
      |> NostrSpamFighter.Policy.Blocklist.changeset(%{
        refresh_status: "importing",
        last_error: "too many entries"
      })
      |> NostrSpamFighter.Repo.update()

    [shown] = Policy.with_runtime_refresh_status([list], executing_ids: [])
    assert shown.refresh_status == "rejected"
    assert shown.last_error == "too many entries"
  end
end
