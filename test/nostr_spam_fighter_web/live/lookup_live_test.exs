defmodule NostrSpamFighterWeb.LookupLiveTest do
  use NostrSpamFighterWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias NostrSpamFighter.Accounts
  alias NostrSpamFighter.Policy
  alias NostrSpamFighter.Policy.Importer

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_admin(%{pubkey: String.duplicate("aa", 32), name: "root", enabled: true})

    conn = Phoenix.ConnTest.init_test_session(conn, %{admin_id: admin.id})

    {:ok, adult} =
      Policy.create_category(%{
        slug: "adult",
        name: "Adult",
        enabled: true,
        blocks_serving: true
      })

    {:ok, list} =
      Policy.create_blocklist(%{
        category_id: adult.id,
        name: "adult-domains",
        source_type: "manual",
        format: "domains"
      })

    assert {:ok, _} = Importer.import_manual(list, "evil.com\n")

    bypass = Bypass.open()
    base = "http://127.0.0.1:#{bypass.port}"

    {:ok, conn: conn, list: list, bypass: bypass, base: base}
  end

  test "blocked domain shows matching list names", %{conn: conn, list: list} do
    {:ok, view, html} = live(conn, ~p"/lookup")
    assert html =~ "Lookup"
    assert has_element?(view, "#lookup-form")
    assert has_element?(view, "#lookup-query")

    html = render_submit(form(view, "#lookup-form", lookup: %{query: "ads.evil.com"}))

    assert has_element?(view, "#lookup-result")
    assert has_element?(view, "#lookup-verdict", "Blocked")
    assert has_element?(view, "#lookup-lists")
    assert has_element?(view, "#lookup-list-#{list.id}", "adult-domains")
    assert html =~ "blocks serving"
  end

  test "clean domain shows an empty list state", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/lookup")
    render_submit(form(view, "#lookup-form", lookup: %{query: "good.example"}))

    assert has_element?(view, "#lookup-verdict", "Not listed")
    assert has_element?(view, "#lookup-lists-empty")
    refute has_element?(view, "#lookup-lists")
  end

  test "empty and invalid queries show errors", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/lookup")

    render_submit(form(view, "#lookup-form", lookup: %{query: "   "}))
    assert has_element?(view, "#lookup-error", "Enter a domain or URL.")
    refute has_element?(view, "#lookup-result")

    render_submit(form(view, "#lookup-form", lookup: %{query: "not a host"}))
    assert has_element?(view, "#lookup-error", "That doesn't look like a valid domain.")
  end

  test "oversized queries are rejected", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/lookup")
    render_submit(form(view, "#lookup-form", lookup: %{query: String.duplicate("a", 5_000)}))
    assert has_element?(view, "#lookup-error", "That value is too long to look up.")
    refute has_element?(view, "#lookup-result")
  end

  test "url lookup follows redirects and reports matching lists", %{
    conn: conn,
    list: list,
    bypass: bypass,
    base: base
  } do
    assert {:ok, _} = Importer.import_manual(list, "evil.com\n127.0.0.1\n")

    Bypass.expect(bypass, "HEAD", "/from", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", base <> "/to")
      |> Plug.Conn.resp(302, "")
    end)

    Bypass.expect(bypass, "HEAD", "/to", fn conn ->
      Plug.Conn.resp(conn, 200, "ok")
    end)

    {:ok, view, _} = live(conn, ~p"/lookup")
    render_submit(form(view, "#lookup-form", lookup: %{query: base <> "/from"}))
    html = render_async(view)

    assert has_element?(view, "#lookup-verdict", "Blocked")
    assert has_element?(view, "#lookup-list-#{list.id}", "adult-domains")
    assert has_element?(view, "#lookup-hosts")
    assert html =~ "127.0.0.1"
  end
end
