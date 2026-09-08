defmodule NostrSpamFighter.Policy.ImporterTest do
  use NostrSpamFighter.DataCase, async: false

  alias NostrSpamFighter.Policy
  alias NostrSpamFighter.Policy.{Cache, Importer}

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

    {:ok, category: category, list: list}
  end

  test "imports domains with underscores", %{list: list} do
    assert {:ok, version} =
             Importer.import_manual(list, "_dmarc.example.com\nad_track.evil.com\n")

    assert version.entry_count == 2
  end

  test "imports labels with hyphens in the third and fourth positions", %{list: list} do
    assert {:ok, version} =
             Importer.import_manual(list, "0------------0-------------0.example.com\n")

    assert version.entry_count == 1
  end

  test "imports domains and matches subdomains only", %{list: list} do
    assert {:ok, version} = Importer.import_manual(list, "Evil.COM.\n# comment\n")
    assert version.status == "active"
    result = Cache.rebuild()
    assert match?({:ok, _}, result), inspect(result)
    assert Cache.generation() > 0

    matches =
      NostrSpamFighter.Policy.Matcher.match_target("https://ads.evil.com/x", "ads.evil.com")

    assert Enum.any?(matches, &(&1.category_slug == "adult"))

    refute NostrSpamFighter.Policy.Matcher.match_target("https://notevil.com", "notevil.com") !=
             []

    no = NostrSpamFighter.Policy.Matcher.match_target("https://notevil.com", "notevil.com")
    assert no == []
  end

  test "failed import keeps previous version", %{list: list} do
    assert {:ok, first} = Importer.import_manual(list, "bad.example\n")
    assert {:error, {:import_failed, failed}} = Importer.import_manual(list, "")
    assert failed.status == "failed"
    list = Policy.get_blocklist!(list.id)
    assert list.active_version_id == first.id
  end

  test "download too large includes the actual size", %{list: list} do
    prev = Application.get_env(:nostr_spam_fighter, :blocklist_max_bytes)

    on_exit(fn ->
      if prev do
        Application.put_env(:nostr_spam_fighter, :blocklist_max_bytes, prev)
      else
        Application.delete_env(:nostr_spam_fighter, :blocklist_max_bytes)
      end
    end)

    Application.put_env(:nostr_spam_fighter, :blocklist_max_bytes, 20)
    body = String.duplicate("x", 100)

    assert {:error, {:import_failed, version}} = Importer.import_manual(list, body)
    assert version.error == "download too large (100 B, limit 20 B)"

    list = Policy.get_blocklist!(list.id)
    assert list.last_error == "download too large (100 B, limit 20 B)"
    assert list.refresh_status == "rejected"
  end

  test "imports more entries than a single Postgres insert allows", %{list: list} do
    body =
      1..10_000
      |> Enum.map_join("\n", fn n -> "host-#{n}.example.com" end)

    assert {:ok, version} = Importer.import_manual(list, body)
    assert version.entry_count == 10_000
    assert Policy.get_blocklist!(list.id).refresh_status == "ok"
  end

  test "stops parsing once the entry cap is exceeded", %{list: list} do
    prev = Application.get_env(:nostr_spam_fighter, :blocklist_max_entries)

    on_exit(fn ->
      if prev do
        Application.put_env(:nostr_spam_fighter, :blocklist_max_entries, prev)
      else
        Application.delete_env(:nostr_spam_fighter, :blocklist_max_entries)
      end
    end)

    Application.put_env(:nostr_spam_fighter, :blocklist_max_entries, 2)

    assert {:error, {:import_failed, version}} =
             Importer.import_manual(list, "a.example\nb.example\nc.example\n")

    assert version.error == "too many entries"
    assert Policy.get_blocklist!(list.id).refresh_status == "rejected"
  end

  test "formats byte sizes for the too-large message" do
    assert Importer.too_large_reason(72_400_000, 70_000_000) ==
             "download too large (72.4 MB, limit 70 MB)"

    assert Importer.format_bytes(20) == "20 B"
    assert Importer.format_bytes(1_500) == "1.5 KB"
    assert Importer.format_count(400) == "400"
    assert Importer.format_count(400_000) == "400K"
    assert Importer.format_count(2_656_393) == "2.7M"
  end

  test "reports parse and save progress", %{list: list} do
    parent = self()
    on_progress = fn progress -> send(parent, {:progress, progress}) end

    body =
      1..40
      |> Enum.map_join("\n", fn n -> "host-#{n}.example.com" end)

    entries = Importer.parse_entries("domains", body, on_progress: on_progress)
    assert length(entries) == 40

    assert_received {:progress,
                     %{phase: "import", stage: "parsing", done: 40, total: 40, percent: 100.0}}

    assert {:ok, version} = Importer.import_remote(list, %{body: body, on_progress: on_progress})
    assert version.entry_count == 40

    assert_received {:progress,
                     %{phase: "import", stage: "saving", done: 40, total: 40, percent: 100.0}}
  end
end
