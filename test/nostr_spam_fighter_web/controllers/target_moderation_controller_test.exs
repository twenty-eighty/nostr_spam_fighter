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

    {:ok, conn: conn, category: cat}
  end

  test "domain moderation matches listed registrable domains", %{conn: conn} do
    body = json_response(get(conn, ~p"/api/v1/domains/ads.evil.com/moderation"), 200)

    assert body["domain"] == "ads.evil.com"
    assert body["registrable_domain"] == "evil.com"
    assert body["url"] == nil
    assert body["status"] == "matched"
    assert body["blacklisted"] == true
    assert body["categories"] == ["adult"]
    assert is_integer(body["policy_generation"])
    assert body["scanned_at"]
  end

  test "clean domain returns clean status", %{conn: conn} do
    body = json_response(get(conn, ~p"/api/v1/domains/good.example/moderation"), 200)

    assert body["status"] == "clean"
    assert body["blacklisted"] == false
    assert body["categories"] == []
    assert body["registrable_domain"] == "good.example"
  end

  test "invalid domain is 400", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/domains/%20/moderation")
    assert json_response(conn, 400)["error"] == "invalid domain"
  end

  test "url moderation uses the host", %{conn: conn} do
    url = "https://ads.evil.com/path?x=1"
    body = json_response(get(conn, ~p"/api/v1/urls/moderation", %{"url" => url}), 200)

    assert body["url"] == "https://ads.evil.com/path?x=1"
    assert body["domain"] == "ads.evil.com"
    assert body["registrable_domain"] == "evil.com"
    assert body["status"] == "matched"
    assert body["blacklisted"] == true
    assert body["categories"] == ["adult"]
  end

  test "url required and invalid url", %{conn: conn} do
    assert json_response(get(conn, ~p"/api/v1/urls/moderation"), 400)["error"] == "url required"

    assert json_response(get(conn, ~p"/api/v1/urls/moderation", %{"url" => "not-a-url"}), 400)[
             "error"
           ] == "invalid url"
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
