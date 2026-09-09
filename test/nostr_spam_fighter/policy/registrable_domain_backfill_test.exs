defmodule NostrSpamFighter.Policy.RegistrableDomainBackfillTest do
  use NostrSpamFighter.DataCase, async: false

  import Ecto.Query

  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Policy
  alias NostrSpamFighter.Policy.{BlocklistEntry, Importer, RegistrableDomainBackfill}

  test "fills null registrable_domain values" do
    {:ok, category} =
      Policy.create_category(%{slug: "adult", name: "Adult", enabled: true, blocks_serving: true})

    {:ok, list} =
      Policy.create_blocklist(%{
        category_id: category.id,
        name: "adult-domains",
        source_type: "manual",
        format: "domains"
      })

    assert {:ok, version} = Importer.import_manual(list, "cdn.blocked.example\n")

    {1, _} =
      from(e in BlocklistEntry, where: e.blocklist_version_id == ^version.id)
      |> Repo.update_all(set: [registrable_domain: nil])

    assert RegistrableDomainBackfill.pending?()
    assert {:ok, 1} = RegistrableDomainBackfill.run()
    refute RegistrableDomainBackfill.pending?()

    entry = Repo.get_by!(BlocklistEntry, blocklist_version_id: version.id)
    assert entry.registrable_domain == "blocked.example"
  end
end
