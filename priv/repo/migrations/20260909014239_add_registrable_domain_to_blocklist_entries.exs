defmodule NostrSpamFighter.Repo.Migrations.AddRegistrableDomainToBlocklistEntries do
  use Ecto.Migration

  # Schema only. Backfill runs after boot via
  # `NostrSpamFighter.Policy.RegistrableDomainBackfill` so migrate can finish
  # before Render's port-scan timeout (large lists are millions of rows).
  def up do
    execute("""
    ALTER TABLE blocklist_entries
    ADD COLUMN IF NOT EXISTS registrable_domain text
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS blocklist_entries_registrable_domain_index
    ON blocklist_entries (registrable_domain)
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS blocklist_entries_registrable_domain_index")
    execute("ALTER TABLE blocklist_entries DROP COLUMN IF EXISTS registrable_domain")
  end
end
