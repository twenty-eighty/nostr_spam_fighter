defmodule NostrSpamFighter.Nostr.IngestorTest do
  use NostrSpamFighter.DataCase, async: false

  alias NostrSpamFighter.Nostr.{Event, EventValidator, Ingestor}
  alias NostrSpamFighter.Moderation.ArticleAddress

  test "persists kind 30023 events whose d tag exceeds varchar(255)" do
    keys = NostrElixir.Keys.generate_keypair()
    d_tag = String.duplicate("n", 400)

    unsigned = NostrElixir.Event.new(keys.public_key, "long identifier", 30023, [["d", d_tag]])
    signed = unsigned |> NostrElixir.Event.sign(keys.secret_key) |> Jason.decode!()

    assert {:ok, valid} = EventValidator.validate(signed)
    assert byte_size(valid["d_tag"]) == 400
    assert byte_size(valid["article_address"]) > 255

    assert {:ok, inserted} = Ingestor.ingest(signed, "wss://relay.example", enqueue_scan: false)
    assert inserted.d_tag == d_tag
    assert inserted.article_address == "30023:#{keys.public_key}:#{d_tag}"

    stored = Repo.get!(Event, inserted.event_id)
    assert stored.d_tag == d_tag

    article = Repo.get_by!(ArticleAddress, kind: 30023, pubkey: keys.public_key, d_tag: d_tag)
    assert article.address == stored.article_address
  end

  test "reingesting the same event from another relay is a no-op insert" do
    {signed, _keys} = signed_article("slug")

    assert {:ok, first} = Ingestor.ingest(signed, "wss://relay.one", enqueue_scan: false)
    assert {:ok, second} = Ingestor.ingest(signed, "wss://relay.two", enqueue_scan: false)
    assert second.event_id == first.event_id

    relays =
      Repo.all(
        from r in NostrSpamFighter.Nostr.EventRelay,
          where: r.event_id == ^first.event_id,
          select: r.relay_url
      )

    assert Enum.sort(relays) == ["wss://relay.one", "wss://relay.two"]
  end

  test "a primary-key race on insert is treated as already seen" do
    {signed, _keys} = signed_article("race")
    {:ok, valid} = EventValidator.validate(signed)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, _} = Ingestor.ingest(signed, "wss://relay.one", enqueue_scan: false)

    assert {:error, changeset} =
             %Event{}
             |> Event.changeset(%{
               event_id: valid["id"],
               kind: valid["kind"],
               pubkey: valid["pubkey"],
               created_at: valid["created_at"],
               d_tag: valid["d_tag"],
               article_address: valid["article_address"],
               raw_event: valid,
               first_seen_at: now,
               last_seen_at: now
             })
             |> Repo.insert()

    assert {:event_id, {_, opts}} = List.keyfind(changeset.errors, :event_id, 0)
    assert opts[:constraint] == :unique

    assert {:ok, again} = Ingestor.ingest(signed, "wss://relay.two", enqueue_scan: false)
    assert again.event_id == valid["id"]
  end

  defp signed_article(d_tag) do
    keys = NostrElixir.Keys.generate_keypair()
    unsigned = NostrElixir.Event.new(keys.public_key, "hello", 30023, [["d", d_tag]])
    signed = unsigned |> NostrElixir.Event.sign(keys.secret_key) |> Jason.decode!()
    {signed, keys}
  end
end
