defmodule NostrSpamFighter.Nostr.LabelPublisherTest do
  use ExUnit.Case, async: true
  alias NostrSpamFighter.Nostr.LabelPublisher
  alias NostrSpamFighter.Policy.Namespace

  test "kind 1985 tags use fixed namespace" do
    tags = LabelPublisher.build_tags(String.duplicate("a", 64), "adult", "wss://relay.example")
    assert ["L", "space.pareto.content"] in tags
    assert ["l", "adult", "space.pareto.content"] in tags
    assert ["e", String.duplicate("a", 64), "wss://relay.example"] in tags
    assert Namespace.content() == "space.pareto.content"
    refute Enum.any?(tags, fn tag -> "space.pareto.moderation" in tag end)
  end
end
