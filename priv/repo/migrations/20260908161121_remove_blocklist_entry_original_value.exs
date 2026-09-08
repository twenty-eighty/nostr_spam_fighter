defmodule NostrSpamFighter.Repo.Migrations.RemoveBlocklistEntryOriginalValue do
  use Ecto.Migration

  def change do
    alter table(:blocklist_entries) do
      remove :original_value, :text, null: false
    end
  end
end
