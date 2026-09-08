defmodule NostrSpamFighterWeb.ArticleModerationControllerTest do
  use NostrSpamFighterWeb.ConnCase, async: false

  alias NostrSpamFighter.{Accounts, Policy, Repo}
  alias NostrSpamFighter.Moderation.ArticleAddress

  setup %{conn: conn} do
    {:ok, key} = Accounts.create_api_key(%{name: "client"})
    conn = put_req_header(conn, "authorization", "Bearer #{key.plaintext}")
    prev_fetcher = Application.get_env(:nostr_spam_fighter, :event_fetcher)

    on_exit(fn ->
      Application.put_env(:nostr_spam_fighter, :event_fetcher, prev_fetcher)
    end)

    {:ok, conn: conn, key: key}
  end

  test "unknown naddr is fetched and scanned on demand", %{conn: conn} do
    keys = NostrElixir.Keys.generate_keypair()

    unsigned =
      NostrElixir.Event.new(keys.public_key, "plain article", 30023, [["d", "on-demand"]])

    signed = unsigned |> NostrElixir.Event.sign(keys.secret_key) |> Jason.decode!()

    Application.put_env(:nostr_spam_fighter, :event_fetcher, fn relays, filter, _opts ->
      assert "wss://hint.example" in relays
      assert 30023 in filter.kinds
      assert keys.public_key in filter.authors
      {:ok, [signed]}
    end)

    {:ok, naddr} =
      NostrElixir.Nip19.Address.encode_naddr(30023, keys.public_key, "on-demand", [
        "wss://hint.example"
      ])

    body = json_response(get(conn, ~p"/api/v1/articles/#{naddr}/moderation"), 200)
    assert body["status"] == "clean"
    assert body["event_id"] == signed["id"]
    assert body["blacklisted"] == false
    assert body["address"] == "30023:#{keys.public_key}:on-demand"
  end

  test "unknown naddr is not clean", %{conn: conn} do
    {:ok, naddr} =
      NostrElixir.Nip19.Address.encode_naddr(30023, String.duplicate("ab", 32), "missing")

    conn = get(conn, ~p"/api/v1/articles/#{naddr}/moderation")
    body = json_response(conn, 200)
    assert body["status"] == "unknown"
    assert body["blacklisted"] == nil
    assert body["categories"] == []
  end

  test "malformed naddr is 400", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/articles/not-an-naddr/moderation")
    assert json_response(conn, 400)["error"] == "malformed naddr"
  end

  test "wrong kind is 422", %{conn: conn} do
    {:ok, naddr} = NostrElixir.Nip19.Address.encode_naddr(1, String.duplicate("ab", 32), "x")
    conn = get(conn, ~p"/api/v1/articles/#{naddr}/moderation")
    assert json_response(conn, 422)
  end

  test "relay hints do not change identity", %{conn: conn} do
    pubkey = String.duplicate("cd", 32)
    {:ok, a} = NostrElixir.Nip19.Address.encode_naddr(30023, pubkey, "slug", ["wss://a.example"])
    {:ok, b} = NostrElixir.Nip19.Address.encode_naddr(30023, pubkey, "slug", ["wss://b.example"])
    one = json_response(get(conn, ~p"/api/v1/articles/#{a}/moderation"), 200)
    two = json_response(get(conn, ~p"/api/v1/articles/#{b}/moderation"), 200)
    assert one["address"] == two["address"]
    assert one["address"] == "30023:#{pubkey}:slug"
  end

  test "requires bearer key and not query string", %{conn: conn, key: key} do
    bare = build_conn()
    {:ok, naddr} = NostrElixir.Nip19.Address.encode_naddr(30023, String.duplicate("ab", 32), "z")
    assert json_response(get(bare, ~p"/api/v1/articles/#{naddr}/moderation"), 401)

    assert json_response(
             get(bare, "/api/v1/articles/#{naddr}/moderation?api_key=#{key.plaintext}"),
             401
           )

    conn = recycle(conn) |> put_req_header("authorization", "Bearer #{key.plaintext}")
    assert json_response(get(conn, ~p"/api/v1/articles/#{naddr}/moderation"), 200)
  end

  test "batch preserves order and limits", %{conn: conn} do
    {:ok, a} = NostrElixir.Nip19.Address.encode_naddr(30023, String.duplicate("11", 32), "a")
    {:ok, b} = NostrElixir.Nip19.Address.encode_naddr(30023, String.duplicate("22", 32), "b")

    conn = post(conn, ~p"/api/v1/articles/moderation/check", %{naddrs: [a, b]})
    body = json_response(conn, 200)
    assert Enum.map(body["results"], & &1["naddr"]) == [a, b]
  end

  test "matched blacklisted when blocks_serving", %{conn: conn} do
    pubkey = String.duplicate("ef", 32)

    {:ok, cat} =
      Policy.create_category(%{
        slug: "malware",
        name: "Malware",
        enabled: true,
        blocks_serving: true
      })

    {:ok, article} =
      %ArticleAddress{}
      |> ArticleAddress.changeset(%{
        kind: 30023,
        pubkey: pubkey,
        d_tag: "post",
        address: "30023:#{pubkey}:post",
        current_event_id: String.duplicate("1", 64),
        current_event_created_at: 1
      })
      |> Repo.insert()

    {:ok, _} =
      %NostrSpamFighter.Moderation.ArticleModerationState{}
      |> NostrSpamFighter.Moderation.ArticleModerationState.changeset(%{
        article_address_id: article.id,
        event_id: article.current_event_id,
        status: "matched",
        blacklisted: true,
        policy_generation: 1
      })
      |> Repo.insert()
      |> then(fn {:ok, state} ->
        Repo.insert(%NostrSpamFighter.Moderation.ArticleModerationCategory{
          article_moderation_state_id: state.id,
          category_id: cat.id,
          slug: "malware"
        })
      end)

    Application.put_env(:nostr_spam_fighter, :event_fetcher, fn _, _, _ ->
      flunk("cached moderation results must not hit relays")
    end)

    {:ok, naddr} = NostrElixir.Nip19.Address.encode_naddr(30023, pubkey, "post")
    body = json_response(get(conn, ~p"/api/v1/articles/#{naddr}/moderation"), 200)
    assert body["blacklisted"] == true
    assert body["status"] == "matched"
    assert body["categories"] == ["malware"]
  end
end
