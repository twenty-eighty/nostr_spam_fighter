defmodule NostrSpamFighterWeb.SettingsLiveTest do
  use NostrSpamFighterWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias NostrSpamFighter.Accounts
  alias NostrSpamFighter.Scanner.{RedirectResolver, SkipHosts}

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_admin(%{pubkey: String.duplicate("aa", 32), name: "root", enabled: true})

    conn = Phoenix.ConnTest.init_test_session(conn, %{admin_id: admin.id})
    {:ok, conn: conn}
  end

  test "lists recommended skip hosts and can add and remove one", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/settings")

    assert html =~ "Skip redirect fetch"
    assert has_element?(view, "#skip-host-form")
    assert has_element?(view, "#skip-hosts", "blossom.primal.net")
    assert has_element?(view, "#skip-hosts", "m.primal.net")

    render_submit(form(view, "#skip-host-form", skip_host: %{host: "https://void.cat/x.png"}))

    assert has_element?(view, "#skip-hosts", "void.cat")
    assert SkipHosts.member?("void.cat")

    result = RedirectResolver.resolve("https://void.cat/x.png")
    assert result.status == "skipped_host"

    row = Enum.find(SkipHosts.list(), &(&1.host == "void.cat"))
    render_click(element(view, "#skip-host-delete-#{row.id}"))
    refute has_element?(view, "#skip-hosts", "void.cat")
    refute SkipHosts.member?("void.cat")
  end

  test "rejects a duplicate skip host", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/settings")

    render_submit(form(view, "#skip-host-form", skip_host: %{host: "blossom.primal.net"}))
    assert has_element?(view, "#skip-host-form", "has already been taken")
  end
end
