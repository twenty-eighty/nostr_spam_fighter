defmodule NostrSpamFighterWeb.AdminLiveTest do
  use NostrSpamFighterWeb.ConnCase, async: false
  import Ecto.Query
  import Phoenix.LiveViewTest
  alias NostrSpamFighter.Accounts
  alias NostrSpamFighter.Policy

  setup %{conn: conn} do
    prev_env = System.get_env("INITIAL_ADMIN_PUBKEY")
    prev_app = Application.get_env(:nostr_spam_fighter, :initial_admin_pubkey)

    on_exit(fn ->
      if prev_env,
        do: System.put_env("INITIAL_ADMIN_PUBKEY", prev_env),
        else: System.delete_env("INITIAL_ADMIN_PUBKEY")

      Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, prev_app)
    end)

    {:ok, admin} =
      Accounts.create_admin(%{pubkey: String.duplicate("aa", 32), name: "root", enabled: true})

    conn = Phoenix.ConnTest.init_test_session(conn, %{admin_id: admin.id})
    {:ok, conn: conn, admin: admin}
  end

  test "protected liveviews require session when an admin pubkey is configured", %{conn: conn} do
    System.put_env("INITIAL_ADMIN_PUBKEY", String.duplicate("aa", 32))
    Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, String.duplicate("aa", 32))

    bare = build_conn()
    assert {:error, {:redirect, %{to: "/login"}}} = live(bare, ~p"/dashboard")
    {:ok, _view, html} = live(conn, ~p"/dashboard")
    assert html =~ "Operations"
  end

  test "admin UI is open when no admin pubkey is configured" do
    System.delete_env("INITIAL_ADMIN_PUBKEY")
    Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, nil)

    {:ok, _view, html} = live(build_conn(), ~p"/dashboard")
    assert html =~ "Operations"
  end

  test "dashboard shows current server activity", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/dashboard")
    assert has_element?(view, "#server-activity")
    assert has_element?(view, "#activity-idle")

    {:ok, job} =
      %{event_id: String.duplicate("ab", 32)}
      |> NostrSpamFighter.Jobs.ScanEventWorker.new()
      |> Oban.insert()

    send(view.pid, :tick)
    assert render(view)
    assert has_element?(view, "#activity-queued", "scan waiting")
    assert has_element?(view, "#activity-waiting", "scan waiting")
    refute has_element?(view, "#activity-idle")

    from(j in Oban.Job, where: j.id == ^job.id)
    |> NostrSpamFighter.Repo.update_all(set: [state: "executing"])

    send(view.pid, :tick)
    assert render(view)
    assert has_element?(view, "#activity-job-#{job.id}", "Scanning")
    refute has_element?(view, "#activity-idle")
  end

  test "category and relay management", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/categories")
    html = render_submit(form(view, "#category-form", category: %{slug: "spam", name: "Spam"}))
    assert html =~ "spam"
    assert has_element?(view, "#category_slug")
    refute has_element?(view, ~s(#category_slug[value="spam"]))
    refute has_element?(view, ~s(#category_name[value="Spam"]))

    {:ok, view, html} = live(conn, ~p"/relays")
    assert has_element?(view, "#ingest-start")
    assert has_element?(view, "#ingest-stop")
    assert html =~ "Event loading:"

    html =
      render_submit(
        form(view, "form", relay: %{url: "wss://relay.example.com", read_enabled: "true"})
      )

    assert html =~ "wss://relay.example.com"
  end

  test "blocklist form lists default categories", %{conn: conn} do
    System.delete_env("INITIAL_ADMIN_PUBKEY")
    Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, nil)

    {:ok, view, html} = live(conn, ~p"/blocklists")
    assert html =~ "Adult"
    assert has_element?(view, "#blocklist-form")
    refute has_element?(view, "#empty-categories")

    adult = Enum.find(Policy.list_categories(), &(&1.slug == "adult"))

    html =
      render_submit(
        form(view, "#blocklist-form",
          blocklist: %{
            name: "Adult hosts",
            category_id: adult.id,
            source_type: "manual",
            format: "domains"
          }
        )
      )

    assert html =~ "Adult hosts"
    assert html =~ "0 entries"
    assert html =~ "last read never"
    refute has_element?(view, ~s(#blocklist_name[value="Adult hosts"]))

    html =
      render_submit(
        form(view, "#blocklist-form",
          blocklist: %{
            name: "Adult hosts",
            category_id: adult.id,
            source_type: "manual",
            format: "domains"
          }
        )
      )

    assert html =~ "already exists"
    assert html =~ "Adult hosts"
    assert Enum.count(Policy.list_blocklists(), &(&1.name == "Adult hosts")) == 1

    list = Enum.find(Policy.list_blocklists(), &(&1.name == "Adult hosts"))
    assert has_element?(view, "#blocklist-#{list.id}")
    render_click(element(view, "#delete-blocklist-#{list.id}"))
    refute has_element?(view, "#blocklist-#{list.id}")
    assert Policy.list_blocklists() == []
  end

  test "blocklist index can disable and enable a list", %{conn: conn} do
    System.delete_env("INITIAL_ADMIN_PUBKEY")
    Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, nil)

    [adult | _] = Policy.ensure_default_categories()

    {:ok, list} =
      Policy.create_blocklist(%{
        name: "Toggle me",
        category_id: adult.id,
        source_type: "manual",
        format: "domains",
        enabled: true
      })

    {:ok, view, _} = live(conn, ~p"/blocklists")
    assert has_element?(view, "#blocklist-enabled-#{list.id}", "enabled")
    assert has_element?(view, "#toggle-blocklist-#{list.id}", "Disable")

    view |> element("#toggle-blocklist-#{list.id}") |> render_click()

    assert has_element?(view, "#blocklist-enabled-#{list.id}", "disabled")
    assert has_element?(view, "#toggle-blocklist-#{list.id}", "Enable")
    refute Policy.get_blocklist!(list.id).enabled
  end

  test "remote blocklist shows download progress", %{conn: conn} do
    System.delete_env("INITIAL_ADMIN_PUBKEY")
    Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, nil)

    {:ok, view, _} = live(conn, ~p"/blocklists")
    adult = Enum.find(Policy.list_categories(), &(&1.slug == "adult"))

    render_submit(
      form(view, "#blocklist-form",
        blocklist: %{
          name: "Remote hosts",
          category_id: adult.id,
          source_type: "remote",
          source_url: "https://example.com/remote-hosts.txt",
          format: "domains"
        }
      )
    )

    list = Enum.find(Policy.list_blocklists(), &(&1.name == "Remote hosts"))
    assert has_element?(view, "#blocklist-progress-#{list.id}", "Queued")
    assert has_element?(view, "#refresh-blocklist-#{list.id}", "Refresh")
    refute has_element?(view, "#refresh-blocklist-#{list.id}:disabled")
    refute has_element?(view, "#download-queue-summary")
  end

  test "blocklist index distinguishes downloading from queued", %{conn: conn} do
    System.delete_env("INITIAL_ADMIN_PUBKEY")
    Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, nil)

    [adult | _] = Policy.ensure_default_categories()

    {:ok, downloading} =
      Policy.create_blocklist(%{
        name: "Active download",
        category_id: adult.id,
        source_type: "remote",
        source_url: "https://example.com/active.txt",
        format: "domains"
      })

    {:ok, queued} =
      Policy.create_blocklist(%{
        name: "Waiting list",
        category_id: adult.id,
        source_type: "remote",
        source_url: "https://example.com/waiting.txt",
        format: "domains"
      })

    {:ok, _} =
      queued
      |> NostrSpamFighter.Policy.Blocklist.changeset(%{refresh_status: "queued"})
      |> NostrSpamFighter.Repo.update()

    {:ok, job} =
      %{blocklist_id: downloading.id}
      |> NostrSpamFighter.Jobs.RefreshBlocklistWorker.new()
      |> Oban.insert()

    from(j in Oban.Job, where: j.id == ^job.id)
    |> NostrSpamFighter.Repo.update_all(set: [state: "executing"])

    {:ok, view, _} = live(conn, ~p"/blocklists")
    assert has_element?(view, "#blocklist-progress-#{downloading.id}", "Downloading")
    assert has_element?(view, "#blocklist-progress-#{queued.id}", "Queued")
    assert has_element?(view, "#refresh-blocklist-#{downloading.id}", "Refresh")
    assert has_element?(view, "#refresh-blocklist-#{queued.id}", "Refresh")
    assert has_element?(view, "#refresh-blocklist-#{downloading.id}:disabled")
    refute has_element?(view, "#refresh-blocklist-#{queued.id}:disabled")
    refute has_element?(view, "#download-queue-summary")

    send(view.pid, {
      :blocklist_download_progress,
      downloading.id,
      %{bytes: 1_500_000, total: 10_000_000, percent: 15.0, bytes_per_sec: 250_000}
    })

    assert render(view)
    assert has_element?(view, "#blocklist-download-#{downloading.id}")
    assert has_element?(view, "#blocklist-download-speed-#{downloading.id}", "1.5 MB / 10 MB")
    assert has_element?(view, "#blocklist-download-speed-#{downloading.id}", "250 KB/s")

    send(view.pid, {
      :blocklist_download_progress,
      queued.id,
      %{bytes: 9_000_000, total: 10_000_000, percent: 90.0, bytes_per_sec: 100_000}
    })

    assert render(view)
    refute has_element?(view, "#blocklist-download-#{queued.id}")

    from(j in Oban.Job, where: j.id == ^job.id)
    |> NostrSpamFighter.Repo.update_all(set: [state: "completed"])

    {:ok, _} =
      downloading
      |> NostrSpamFighter.Policy.Blocklist.changeset(%{refresh_status: "ok"})
      |> NostrSpamFighter.Repo.update()

    send(view.pid, {:blocklist_refreshed, downloading.id})
    assert render(view)
    refute has_element?(view, "#blocklist-download-#{downloading.id}")
    refute has_element?(view, "#blocklist-progress-#{downloading.id}")
  end

  test "blocklist index shows import progress", %{conn: conn} do
    System.delete_env("INITIAL_ADMIN_PUBKEY")
    Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, nil)

    [adult | _] = Policy.ensure_default_categories()

    {:ok, importing} =
      Policy.create_blocklist(%{
        name: "Active import",
        category_id: adult.id,
        source_type: "remote",
        source_url: "https://example.com/import.txt",
        format: "domains"
      })

    {:ok, _} =
      importing
      |> NostrSpamFighter.Policy.Blocklist.changeset(%{refresh_status: "importing"})
      |> NostrSpamFighter.Repo.update()

    {:ok, job} =
      %{blocklist_id: importing.id}
      |> NostrSpamFighter.Jobs.RefreshBlocklistWorker.new()
      |> Oban.insert()

    from(j in Oban.Job, where: j.id == ^job.id)
    |> NostrSpamFighter.Repo.update_all(set: [state: "executing"])

    {:ok, view, _} = live(conn, ~p"/blocklists")
    assert has_element?(view, "#blocklist-progress-#{importing.id}", "Importing")

    send(view.pid, {
      :blocklist_download_progress,
      importing.id,
      %{phase: "import", stage: "saving", done: 400_000, total: 2_656_393, percent: 15.1}
    })

    assert render(view)
    assert has_element?(view, "#blocklist-download-#{importing.id}")
    assert has_element?(view, "#blocklist-download-speed-#{importing.id}", "Saving")
    assert has_element?(view, "#blocklist-download-speed-#{importing.id}", "400K / 2.7M")

    send(view.pid, {
      :blocklist_download_progress,
      importing.id,
      %{phase: "import", stage: "parsing", done: 1_200_000, total: 2_656_393, percent: 45.2}
    })

    assert render(view)
    assert has_element?(view, "#blocklist-download-speed-#{importing.id}", "Parsing")
    assert has_element?(view, "#blocklist-download-speed-#{importing.id}", "1.2M / 2.7M")
  end

  test "blocklist index shows the failure reason", %{conn: conn} do
    System.delete_env("INITIAL_ADMIN_PUBKEY")
    Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, nil)

    [adult | _] = Policy.ensure_default_categories()

    {:ok, failed} =
      Policy.create_blocklist(%{
        name: "Broken list",
        category_id: adult.id,
        source_type: "remote",
        source_url: "https://example.com/broken.txt",
        format: "domains"
      })

    {:ok, _} =
      failed
      |> NostrSpamFighter.Policy.Blocklist.changeset(%{
        refresh_status: "queued",
        last_error: "HTTP 404 Not Found"
      })
      |> NostrSpamFighter.Repo.update()

    {:ok, view, _} = live(conn, ~p"/blocklists")
    assert has_element?(view, "#blocklist-progress-#{failed.id}", "Queued")
    assert has_element?(view, "#blocklist-error-#{failed.id}", "HTTP 404 Not Found")
  end

  test "api key create shows secret once", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/api-keys")
    html = render_submit(form(view, "form", name: "prod"))
    assert html =~ "Copy now: nsf_"
    {:ok, _view, html} = live(conn, ~p"/api-keys")
    refute html =~ "Copy now:"
  end
end
