defmodule NostrSpamFighter.Policy.LookupTest do
  use NostrSpamFighter.DataCase, async: false

  alias NostrSpamFighter.Moderation.TargetState
  alias NostrSpamFighter.Policy
  alias NostrSpamFighter.Policy.{Importer, Lookup}

  setup do
    {:ok, adult} =
      Policy.create_category(%{
        slug: "adult",
        name: "Adult",
        enabled: true,
        blocks_serving: true
      })

    {:ok, ads} =
      Policy.create_category(%{
        slug: "ads",
        name: "Ads",
        enabled: true,
        blocks_serving: false
      })

    {:ok, adult_primary} =
      Policy.create_blocklist(%{
        category_id: adult.id,
        name: "adult-primary",
        source_type: "manual",
        format: "domains"
      })

    {:ok, adult_mirror} =
      Policy.create_blocklist(%{
        category_id: adult.id,
        name: "adult-mirror",
        source_type: "manual",
        format: "domains"
      })

    {:ok, ads_list} =
      Policy.create_blocklist(%{
        category_id: ads.id,
        name: "ads-trackers",
        source_type: "manual",
        format: "domains"
      })

    {:ok, disabled_list} =
      Policy.create_blocklist(%{
        category_id: adult.id,
        name: "adult-disabled",
        source_type: "manual",
        format: "domains"
      })

    assert {:ok, _} = Importer.import_manual(adult_primary, "evil.com\n")
    assert {:ok, _} = Importer.import_manual(adult_mirror, "evil.com\n")
    assert {:ok, _} = Importer.import_manual(ads_list, "evil.com\n")
    assert {:ok, _} = Importer.import_manual(disabled_list, "evil.com\n")
    assert {:ok, _} = Policy.set_blocklist_enabled(disabled_list, false)

    {:ok, adult_primary: adult_primary, adult_mirror: adult_mirror, ads_list: ads_list}
  end

  test "returns every enabled list that matches a host", %{
    adult_primary: adult_primary,
    adult_mirror: adult_mirror,
    ads_list: ads_list
  } do
    assert {:ok, %{host: "ads.evil.com", registrable_domain: "evil.com", lists: lists}} =
             Lookup.lists_for_host("ads.evil.com")

    names = Enum.map(lists, & &1.name)
    assert "adult-primary" in names
    assert "adult-mirror" in names
    assert "ads-trackers" in names
    refute "adult-disabled" in names

    assert Enum.any?(lists, &(&1.id == adult_primary.id and &1.blocks_serving == true))
    assert Enum.any?(lists, &(&1.id == adult_mirror.id and &1.category_slug == "adult"))
    assert Enum.any?(lists, &(&1.id == ads_list.id and &1.blocks_serving == false))
  end

  test "rejects invalid hosts" do
    assert Lookup.lists_for_host(".") == {:error, :invalid_domain}
    assert Lookup.lists_for_host("not a host") == {:error, :invalid_domain}
    assert Lookup.lists_for_host("") == {:error, :invalid_domain}
  end

  test "target state includes all matching lists for a domain" do
    assert {:ok, result} = TargetState.lookup_domain("www.evil.com")
    assert result.blacklisted
    assert result.status == "matched"
    assert result.categories == ["ads", "adult"]
    assert Enum.map(result.lists, & &1.name) == ["ads-trackers", "adult-mirror", "adult-primary"]
  end

  test "clean hosts have no lists" do
    assert {:ok, %{lists: []}} = Lookup.lists_for_host("good.example")
    assert {:ok, result} = TargetState.lookup_domain("good.example")
    assert result.status == "clean"
    assert result.lists == []
  end
end
