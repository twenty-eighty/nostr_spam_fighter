defmodule NostrSpamFighter.Policy.NamespaceTest do
  use ExUnit.Case, async: true

  test "public classification namespace is space.pareto.content" do
    assert NostrSpamFighter.Policy.Namespace.content() == "space.pareto.content"
  end

  test "namespace cannot accidentally change" do
    {:ok, ast} =
      Code.string_to_quoted(
        File.read!(
          Path.join([
            __DIR__,
            "..",
            "..",
            "..",
            "lib",
            "nostr_spam_fighter",
            "policy",
            "namespace.ex"
          ])
        )
      )

    assert inspect(ast) =~ "space.pareto.content"
    refute inspect(ast) =~ "space.pareto.moderation"
  end
end
