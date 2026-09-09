defmodule NostrSpamFighter.Jobs.RefreshBlocklistWorkerTest do
  use NostrSpamFighter.DataCase, async: false
  use Oban.Testing, repo: NostrSpamFighter.Repo

  alias NostrSpamFighter.Policy
  alias NostrSpamFighter.Jobs.RefreshBlocklistWorker
  alias NostrSpamFighter.Policy.BlocklistDownloader

  setup do
    [adult | _] = Policy.ensure_default_categories()
    bypass = Bypass.open()

    {:ok, list} =
      Policy.create_blocklist(%{
        name: "Remote test #{bypass.port}",
        category_id: adult.id,
        source_type: "remote",
        source_url: "http://127.0.0.1:#{bypass.port}/list.txt",
        format: "domains"
      })

    {:ok, list: list, bypass: bypass}
  end

  test "records a readable HTTP error", %{list: list, bypass: bypass} do
    Bypass.expect(bypass, "GET", "/list.txt", fn conn ->
      Plug.Conn.resp(conn, 404, "missing")
    end)

    assert {:error, {:import_failed, version}} = RefreshBlocklistWorker.refresh(list)
    assert version.error =~ "HTTP 404"

    list = Policy.get_blocklist!(list.id)
    assert list.last_error =~ "HTTP 404"
    assert list.refresh_status == "failed"
  end

  test "follows redirects and imports entries", %{list: list, bypass: bypass} do
    Bypass.expect(bypass, "GET", "/list.txt", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "/final.txt")
      |> Plug.Conn.resp(302, "")
    end)

    Bypass.expect(bypass, "GET", "/final.txt", fn conn ->
      Plug.Conn.resp(conn, 200, "evil.example\n")
    end)

    assert {:ok, version} = RefreshBlocklistWorker.refresh(list)
    assert version.entry_count == 1

    list = Policy.get_blocklist!(list.id)
    assert list.last_error == nil
    assert list.refresh_status == "ok"
    assert list.active_version.entry_count == 1
  end

  test "marks downloading while the request is in flight", %{list: list, bypass: bypass} do
    parent = self()

    Bypass.expect(bypass, "GET", "/list.txt", fn conn ->
      send(parent, {:started, self()})

      receive do
        :go -> :ok
      after
        2_000 -> raise "blocked download was not released"
      end

      Plug.Conn.resp(conn, 200, "evil.example\n")
    end)

    task = Task.async(fn -> RefreshBlocklistWorker.refresh(list) end)
    assert_receive {:started, bypass_pid}, 1_000
    assert Policy.get_blocklist!(list.id).refresh_status == "downloading"
    send(bypass_pid, :go)
    assert {:ok, _version} = Task.await(task)
    assert Policy.get_blocklist!(list.id).refresh_status == "ok"
  end

  test "does not retry a download that is too large", %{list: list, bypass: bypass} do
    prev = Application.get_env(:nostr_spam_fighter, :blocklist_max_bytes)

    on_exit(fn ->
      if prev do
        Application.put_env(:nostr_spam_fighter, :blocklist_max_bytes, prev)
      else
        Application.delete_env(:nostr_spam_fighter, :blocklist_max_bytes)
      end
    end)

    Application.put_env(:nostr_spam_fighter, :blocklist_max_bytes, 20)

    Bypass.expect(bypass, "GET", "/list.txt", fn conn ->
      Plug.Conn.resp(conn, 200, String.duplicate("x", 100))
    end)

    assert :ok = perform_job(RefreshBlocklistWorker, %{blocklist_id: list.id})
    list = Policy.get_blocklist!(list.id)
    assert list.refresh_status == "rejected"
    assert list.last_error =~ "download too large"
  end

  test "does not auto-queue a list that already failed to import", %{list: list} do
    {:ok, _} =
      list
      |> NostrSpamFighter.Policy.Blocklist.changeset(%{
        refresh_status: "failed",
        last_error: "too many entries"
      })
      |> NostrSpamFighter.Repo.update()

    NostrSpamFighter.Repo.delete_all(Oban.Job)

    assert :ok = RefreshBlocklistWorker.enqueue(list.id)
    refute_enqueued(worker: RefreshBlocklistWorker, args: %{blocklist_id: list.id})
    assert Policy.get_blocklist!(list.id).refresh_status == "failed"

    assert :ok = RefreshBlocklistWorker.enqueue(list.id, force: true)
    assert_enqueued(worker: RefreshBlocklistWorker, args: %{blocklist_id: list.id})
    assert Policy.get_blocklist!(list.id).refresh_status == "queued"
  end

  test "enqueue after a completed job still queues a new fetch", %{list: list} do
    from(j in Oban.Job,
      where: j.worker == "NostrSpamFighter.Jobs.RefreshBlocklistWorker",
      where: fragment("? ->> 'blocklist_id' = ?", j.args, ^list.id)
    )
    |> NostrSpamFighter.Repo.update_all(set: [state: "completed"])

    assert :ok = RefreshBlocklistWorker.enqueue(list.id)
    assert_enqueued(worker: RefreshBlocklistWorker, args: %{blocklist_id: list.id})
    assert Policy.get_blocklist!(list.id).refresh_status == "queued"
  end

  test "records an Oban exception on the blocklist", %{list: list} do
    {:ok, list} =
      list
      |> NostrSpamFighter.Policy.Blocklist.changeset(%{refresh_status: "importing"})
      |> NostrSpamFighter.Repo.update()

    job = %Oban.Job{
      worker: "NostrSpamFighter.Jobs.RefreshBlocklistWorker",
      args: %{"blocklist_id" => list.id}
    }

    assert :ok =
             RefreshBlocklistWorker.record_job_exception(job, %{
               reason: %Oban.TimeoutError{message: "timed out", reason: :timeout}
             })

    list = Policy.get_blocklist!(list.id)
    assert list.refresh_status == "failed"
    assert list.last_error == "timed out after 15 minutes"
  end

  test "snoozes refresh when memory is tight", %{list: list} do
    prev_pressure = Application.get_env(:nostr_spam_fighter, :memory_pressure, :unset)
    prev_fun = Application.get_env(:nostr_spam_fighter, :memory_usage_fun, :unset)
    prev_limit = Application.get_env(:nostr_spam_fighter, :memory_limit_bytes, :unset)

    Application.put_env(:nostr_spam_fighter, :memory_pressure, true)
    Application.put_env(:nostr_spam_fighter, :memory_usage_fun, fn -> 100 end)
    Application.put_env(:nostr_spam_fighter, :memory_limit_bytes, 10)

    on_exit(fn ->
      restore_env(:memory_pressure, prev_pressure)
      restore_env(:memory_usage_fun, prev_fun)
      restore_env(:memory_limit_bytes, prev_limit)
    end)

    assert {:snooze, 30} = perform_job(RefreshBlocklistWorker, %{blocklist_id: list.id})
  end

  test "explains timeout errors" do
    message = BlocklistDownloader.format_exception(%{reason: :timeout}, 15_000, 120_000)
    assert message == "timed out after 120s waiting for the server"
    assert BlocklistDownloader.format_exception(%{reason: :nxdomain}) == "DNS lookup failed"
  end

  defp restore_env(key, :unset), do: Application.delete_env(:nostr_spam_fighter, key)
  defp restore_env(key, value), do: Application.put_env(:nostr_spam_fighter, key, value)
end
