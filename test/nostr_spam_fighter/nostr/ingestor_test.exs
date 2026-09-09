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
end
