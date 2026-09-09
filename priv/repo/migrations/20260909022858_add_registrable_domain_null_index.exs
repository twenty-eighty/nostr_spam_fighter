defmodule NostrSpamFighter.Repo.Migrations.AddRegistrableDomainNullIndex do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:blocklist_entries, [:id],
                           where:
                             "registrable_domain IS NULL AND rule_type IN ('host', 'domain')",
                           name: :blocklist_entries_registrable_domain_pending_index
                         )
  end
end
