defmodule NostrSpamFighter.Repo.Migrations.AddRegistrableDomainToBlocklistEntries do
  use Ecto.Migration

  import Ecto.Query

  def up do
    alter table(:blocklist_entries) do
      add :registrable_domain, :text
    end

    create index(:blocklist_entries, [:registrable_domain])

    flush()

    backfill_registrable_domains()
  end

  def down do
    drop_if_exists index(:blocklist_entries, [:registrable_domain])

    alter table(:blocklist_entries) do
      remove :registrable_domain
    end
  end

  defp backfill_registrable_domains do
    alias NostrSpamFighter.Repo
    alias NostrSpamFighter.Policy.PublicSuffix

    Repo.transaction(
      fn ->
        from(e in "blocklist_entries",
          where: e.rule_type in ^["host", "domain"],
          where: is_nil(e.registrable_domain),
          select: %{id: e.id, normalized_value: e.normalized_value}
        )
        |> Repo.stream(max_rows: 2_000)
        |> Stream.chunk_every(500)
        |> Enum.each(fn chunk ->
          Enum.each(chunk, fn row ->
            domain =
              PublicSuffix.registrable_domain(row.normalized_value) || row.normalized_value

            from(e in "blocklist_entries", where: e.id == ^row.id)
            |> Repo.update_all(set: [registrable_domain: domain])
          end)
        end)
      end,
      timeout: :infinity
    )
  end
end
