defmodule NostrSpamFighterWeb.TargetModerationControllerTest do
  use NostrSpamFighterWeb.ConnCase, async: false

  alias NostrSpamFighter.{Accounts, Policy}
  alias NostrSpamFighter.Policy.Importer

  setup %{conn: conn} do
    {:ok, key} = Accounts.create_api_key(%{name: "client"})
    conn = put_req_header(conn, "authorization", "Bearer #{key.plaintext}")

    {:ok, cat} =
      Policy.create_category(%{
        slug: "adult",
        name: "Adult",
        enabled: true,
        blocks_serving: true
      })

    {:ok, list} =
      Policy.create_blocklist(%{
        category_id: cat.id,
        name: "adult-domains",
        source_type: "manual",
        format: "domains"
      })

    assert {:ok, _} = Importer.import_manual(list, "evil.com\n")

    bypass = Bypass.open()
    base = "http://127.0.0.1:#{bypass.port}"

    {:ok, conn: conn, category: cat, list: list, bypass: bypass, base: base}
  end

  test "domain moderation matches listed registrable domains", %{conn: conn} do
    body = json_response(get(conn, ~p"/api/v1/domains/ads.evil.com/moderation"), 200)

    assert body["domain"] == "ads.evil.com"
    assert body["registrable_domain"] == "evil.com"
    assert body["url"] == nil
    assert body["status"] == "matched"
    assert body["blacklisted"] == true
    assert body["categories"] == ["adult"]

    assert [%{"name" => "adult-domains", "category_slug" => "adult", "blocks_serving" => true}] =
             body["lists"]

    assert body["redirect_count"] == 0
    assert body["resolution_status"] == nil
    assert is_integer(body["policy_generation"])
    assert body["scanned_at"]
  end

  test "clean domain returns clean status", %{conn: conn} do
    body = json_response(get(conn, ~p"/api/v1/domains/good.example/moderation"), 200)

    assert body["status"] == "clean"
    assert body["blacklisted"] == false
    assert body["categories"] == []
    assert body["lists"] == []
    assert body["registrable_domain"] == "good.example"
  end

  test "invalid domain is 400", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/domains/%20/moderation")
    assert json_response(conn, 400)["error"] == "invalid domain"
  end

  test "url moderation follows redirects onto a blocked host", %{
    conn: conn,
    list: list,
    bypass: bypass,
    base: base
  } do
    assert {:ok, _} = Importer.import_manual(list, "evil.com\nlocalhost\n")

    Bypass.expect(bypass, "HEAD", "/safe", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "http://localhost:#{bypass.port}/blocked")
      |> Plug.Conn.resp(302, "")
    end)

    Bypass.expect(bypass, "HEAD", "/blocked", fn conn ->
      Plug.Conn.resp(conn, 200, "ok")
    end)

    prev_level = Logger.level()
    Logger.configure(level: :info)

    on_exit(fn -> Logger.configure(level: prev_level) end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        send(
          self(),
          {:body,
           json_response(get(conn, ~p"/api/v1/urls/moderation", %{"url" => base <> "/safe"}), 200)}
        )
      end)

    assert_received {:body, body}

    assert body["url"] == base <> "/safe"
    assert body["domain"] == "127.0.0.1"
    assert body["status"] == "matched"
    assert body["blacklisted"] == true
    assert body["categories"] == ["adult"]
    assert Enum.any?(body["lists"], &(&1["name"] == "adult-domains"))
    assert body["redirect_count"] == 1
    assert body["final_url"] =~ "localhost"
    assert body["final_domain"] == "localhost"
    assert body["resolution_status"]
    assert log =~ "url moderation start host=127.0.0.1"
    assert log =~ "url moderation blocked host=127.0.0.1 final=localhost redirects=1"
    assert log =~ "cats=adult lists=adult-domains"
  end

  test "clean url with successful fetch stays clean", %{conn: conn, bypass: bypass, base: base} do
    Bypass.expect(bypass, "HEAD", "/ok", fn conn ->
      Plug.Conn.resp(conn, 200, "ok")
    end)

    body = json_response(get(conn, ~p"/api/v1/urls/moderation", %{"url" => base <> "/ok"}), 200)

    assert body["status"] == "clean"
    assert body["blacklisted"] == false
    assert body["categories"] == []
    assert body["redirect_count"] == 0
    assert body["resolution_status"] == "completed"
  end

  test "known media hosts skip redirect fetch", %{conn: conn} do
    url =
      "https://blossom.primal.net/babdc64fcf9e85c0022e866c16a3738a51426556ae10a04267d9d91e2411ce5c.png"

    body = json_response(get(conn, ~p"/api/v1/urls/moderation", %{"url" => url}), 200)

    assert body["status"] == "clean"
    assert body["domain"] == "blossom.primal.net"
    assert body["final_domain"] == "blossom.primal.net"
    assert body["redirect_count"] == 0
    assert body["resolution_status"] == "skipped_host"
  end

  test "url required and invalid url", %{conn: conn} do
    assert json_response(get(conn, ~p"/api/v1/urls/moderation"), 400)["error"] == "url required"

    assert json_response(get(conn, ~p"/api/v1/urls/moderation", %{"url" => "not-a-url"}), 400)[
             "error"
           ] == "invalid url"
  end

  test "oversized url is 400", %{conn: conn} do
    url = "https://example.com/" <> String.duplicate("a", 4_100)

    assert json_response(get(conn, ~p"/api/v1/urls/moderation", %{"url" => url}), 400)["error"] ==
             "url too long"
  end

  test "requires bearer api key", %{conn: conn} do
    bare = build_conn()
    assert json_response(get(bare, ~p"/api/v1/domains/evil.com/moderation"), 401)

    assert json_response(
             get(conn, ~p"/api/v1/domains/evil.com/moderation"),
             200
           )
  end

  test "non-blocking category is matched but not blacklisted", %{conn: conn} do
    {:ok, cat} =
      Policy.create_category(%{
        slug: "ads",
        name: "Ads",
        enabled: true,
        blocks_serving: false
      })

    {:ok, list} =
      Policy.create_blocklist(%{
        category_id: cat.id,
        name: "ads-domains",
        source_type: "manual",
        format: "domains"
      })

    assert {:ok, _} = Importer.import_manual(list, "tracker.example\n")

    body = json_response(get(conn, ~p"/api/v1/domains/tracker.example/moderation"), 200)
    assert body["status"] == "matched"
    assert body["blacklisted"] == false
    assert body["categories"] == ["ads"]
  end
end
