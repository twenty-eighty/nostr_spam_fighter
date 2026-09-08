defmodule NostrSpamFighter.Policy.BlocklistEnabledTest do
  use NostrSpamFighter.DataCase, async: false

  alias NostrSpamFighter.Policy
  alias NostrSpamFighter.Policy.{Cache, Importer, Matcher}
  alias NostrSpamFighter.Jobs.RefreshBlocklistWorker

  setup do
    {:ok, category} =
      Policy.create_category(%{slug: "adult", name: "Adult", enabled: true, blocks_serving: true})

    {:ok, list} =
      Policy.create_blocklist(%{
        category_id: category.id,
        name: "adult-domains",
        source_type: "manual",
        format: "domains"
      })

    assert {:ok, _} = Importer.import_manual(list, "evil.com\n")
    assert {:ok, _} = Cache.rebuild()

    {:ok, list: Policy.get_blocklist!(list.id)}
  end

  test "disabled blocklists are excluded from matching and cache", %{list: list} do
    assert Matcher.match_target("https://ads.evil.com", "ads.evil.com") != []

    assert {:ok, disabled} = Policy.set_blocklist_enabled(list, false)
    refute disabled.enabled
    assert Matcher.match_target("https://ads.evil.com", "ads.evil.com") == []
    assert Cache.size() == 0

    assert {:error, :disabled} = RefreshBlocklistWorker.enqueue(list.id, force: true)

    assert {:ok, enabled} = Policy.set_blocklist_enabled(disabled, true)
    assert enabled.enabled
    assert Matcher.match_target("https://ads.evil.com", "ads.evil.com") != []
  end
end
