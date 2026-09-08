defmodule NostrSpamFighter.Policy.MatcherTest do
  use ExUnit.Case, async: true
  alias NostrSpamFighter.Policy.Matcher

  test "domain matches host and subdomain only" do
    assert Matcher.domain_match?("evil.com", "evil.com")
    assert Matcher.domain_match?("ads.evil.com", "evil.com")
    refute Matcher.domain_match?("notevil.com", "evil.com")
    refute Matcher.domain_match?("evil.com.attacker.test", "evil.com")
  end
end
