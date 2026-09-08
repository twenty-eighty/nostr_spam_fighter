defmodule NostrSpamFighter.Repo.Migrations.AddBlocklistUniqueness do
  use Ecto.Migration

  def up do
    execute """
    DELETE FROM matches
    WHERE blocklist_id IN (
      SELECT id FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY category_id, name
                 ORDER BY inserted_at, id
               ) AS rn
        FROM blocklists
      ) duplicates
      WHERE rn > 1
    )
    """

    execute """
    DELETE FROM blocklists
    WHERE id IN (
      SELECT id FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY category_id, name
                 ORDER BY inserted_at, id
               ) AS rn
        FROM blocklists
      ) duplicates
      WHERE rn > 1
    )
    """

    execute """
    DELETE FROM matches
    WHERE blocklist_id IN (
      SELECT id FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY source_url
                 ORDER BY inserted_at, id
               ) AS rn
        FROM blocklists
        WHERE source_url IS NOT NULL AND source_url <> ''
      ) duplicates
      WHERE rn > 1
    )
    """

    execute """
    DELETE FROM blocklists
    WHERE id IN (
      SELECT id FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY source_url
                 ORDER BY inserted_at, id
               ) AS rn
        FROM blocklists
        WHERE source_url IS NOT NULL AND source_url <> ''
      ) duplicates
      WHERE rn > 1
    )
    """

    create unique_index(:blocklists, [:category_id, :name])

    create unique_index(:blocklists, [:source_url],
             where: "source_url IS NOT NULL AND source_url <> ''",
             name: :blocklists_source_url_index
           )
  end

  def down do
    drop unique_index(:blocklists, [:source_url], name: :blocklists_source_url_index)
    drop unique_index(:blocklists, [:category_id, :name])
  end
end
