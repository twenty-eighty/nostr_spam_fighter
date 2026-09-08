defmodule NostrSpamFighter.Repo.Migrations.AddBlocklistRefreshStatus do
  use Ecto.Migration

  def change do
    alter table(:blocklists) do
      add :refresh_status, :string, null: false, default: "idle"
    end
  end
end
