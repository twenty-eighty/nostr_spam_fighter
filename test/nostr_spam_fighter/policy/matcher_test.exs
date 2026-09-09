defmodule NostrSpamFighter.Policy.MatcherTest do
  use NostrSpamFighter.DataCase, async: false

  alias NostrSpamFighter.Policy
  alias NostrSpamFighter.Policy.{Cache, Importer, Matcher}

  test "domain matches host and subdomain only" do
    assert Matcher.domain_match?("evil.com", "evil.com")
    assert Matcher.domain_match?("ads.evil.com", "evil.com")
    refute Matcher.domain_match?("notevil.com", "evil.com")
    refute Matcher.domain_match?("evil.com.attacker.test", "evil.com")
  end

  test "keyed cache matches domains without scanning all rules" do
    {:ok, category} =
      Policy.create_category(%{slug: "spam", name: "Spam", enabled: true, blocks_serving: true})

    {:ok, list} =
      Policy.create_blocklist(%{
        category_id: category.id,
        name: "spam-domains",
        source_type: "manual",
        format: "domains"
      })

    assert {:ok, _} = Importer.import_manual(list, "evil.com\ngood.example\n")
    assert {:ok, _} = Cache.rebuild()
    assert Cache.size() >= 2

    matches = Matcher.match_target("https://ads.evil.com/x", "ads.evil.com")
    assert Enum.any?(matches, &(&1.normalized_value == "evil.com"))
    assert Enum.any?(matches, &(&1.category_id == category.id))

    assert Matcher.match_target("https://notevil.com", "notevil.com") == []
  end

  test "registrable-domain collapse treats subdomain listings as the apex domain" do
    {:ok, category} =
      Policy.create_category(%{slug: "adult", name: "Adult", enabled: true, blocks_serving: true})

    {:ok, list} =
      Policy.create_blocklist(%{
        category_id: category.id,
        name: "adult-hosts",
        source_type: "manual",
        format: "domains"
      })

    assert {:ok, _} = Importer.import_manual(list, "cdn.blocked.example\n")
    assert {:ok, _} = Cache.rebuild()

    # Listed subdomain collapses to blocked.example; other hosts under it match.
    matches = Matcher.match_target("https://www.blocked.example/x", "www.blocked.example")
    assert Enum.any?(matches, &(&1.normalized_value == "blocked.example"))
  end
end
