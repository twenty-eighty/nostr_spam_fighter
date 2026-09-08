defmodule NostrSpamFighter.Nostr.EventValidatorTest do
  use ExUnit.Case, async: true
  alias NostrSpamFighter.Nostr.EventValidator

  test "rejects wrong kind and malformed fields" do
    event = %{
      "id" => String.duplicate("a", 64),
      "pubkey" => String.duplicate("b", 64),
      "created_at" => 1,
      "kind" => 1,
      "tags" => [],
      "content" => "hi",
      "sig" => String.duplicate("c", 128)
    }

    assert {:error, :unsupported_kind} = EventValidator.validate(event)
  end

  test "recomputes id from canonical serialization" do
    event = %{
      "pubkey" => String.duplicate("a", 64),
      "created_at" => 1,
      "kind" => 30023,
      "tags" => [["d", "hello"]],
      "content" => "hi"
    }

    id = EventValidator.recompute_id(event)
    assert String.match?(id, ~r/^[0-9a-f]{64}$/)
    assert id == EventValidator.recompute_id(event)
  end

  @tag :nif
  test "accepts a real signed kind 30023 event" do
    keys = NostrElixir.Keys.generate_keypair()
    unsigned = NostrElixir.Event.new(keys.public_key, "hello", 30023, [["d", "slug"]])
    signed = NostrElixir.Event.sign(unsigned, keys.secret_key) |> Jason.decode!()
    assert {:ok, valid} = EventValidator.validate(signed)
    assert valid["d_tag"] == "slug"
    assert valid["article_address"] == "30023:#{keys.public_key}:slug"
  end
end
