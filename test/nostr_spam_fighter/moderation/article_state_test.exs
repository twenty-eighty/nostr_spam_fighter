defmodule NostrSpamFighter.Moderation.ArticleStateTest do
  use NostrSpamFighter.DataCase, async: false

  alias NostrSpamFighter.Moderation.{ArticleAddress, ArticleModerationState, ArticleState}
  alias NostrSpamFighter.Nostr.Ingestor
  alias NostrSpamFighter.Scanner.Pipeline

  test "concurrent refreshes for the same article do not raise" do
    keys = NostrElixir.Keys.generate_keypair()

    unsigned =
      NostrElixir.Event.new(keys.public_key, "https://example.com/a", 30023, [["d", "race"]])

    signed = unsigned |> NostrElixir.Event.sign(keys.secret_key) |> Jason.decode!()

    assert {:ok, event} = Ingestor.ingest(signed, "wss://relay.example", enqueue_scan: false)
    assert {:ok, _scan} = Pipeline.run(event.event_id)

    article = Repo.get_by!(ArticleAddress, kind: 30023, pubkey: keys.public_key, d_tag: "race")
    Repo.delete_all(ArticleModerationState)

    parent = self()

    results =
      1..8
      |> Enum.map(fn _ ->
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
          ArticleState.refresh(article)
        end)
      end)
      |> Task.await_many(5_000)

    assert Enum.all?(results, &match?({:ok, %ArticleModerationState{}}, &1))
    assert Repo.aggregate(ArticleModerationState, :count) == 1
  end

  test "concurrent on-demand scans serialize without constraint errors" do
    keys = NostrElixir.Keys.generate_keypair()

    unsigned =
      NostrElixir.Event.new(keys.public_key, "plain https://example.com/b", 30023, [["d", "lock"]])

    signed = unsigned |> NostrElixir.Event.sign(keys.secret_key) |> Jason.decode!()

    Application.put_env(:nostr_spam_fighter, :event_fetcher, fn _relays, _filter, _opts ->
      {:ok, [signed]}
    end)

    on_exit(fn -> Application.delete_env(:nostr_spam_fighter, :event_fetcher) end)

    data = %{
      kind: 30023,
      pubkey: keys.public_key,
      identifier: "lock",
      relays: ["wss://hint.example"]
    }

    parent = self()

    results =
      1..4
      |> Enum.map(fn _ ->
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
          NostrSpamFighter.Moderation.OnDemand.ensure(data)
        end)
      end)
      |> Task.await_many(15_000)

    assert results == [:ok, :ok, :ok, :ok]
    assert Repo.aggregate(ArticleModerationState, :count) == 1

    state = Repo.one!(ArticleModerationState)
    assert state.status in ["clean", "matched", "partial"]

    # Only one completed scan should win; waiters skip via only_if_needed.
    completed =
      Repo.aggregate(
        from(s in NostrSpamFighter.Moderation.Scan, where: s.status != "running"),
        :count
      )

    assert completed == 1
  end
end
