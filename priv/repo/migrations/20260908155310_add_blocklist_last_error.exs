defmodule NostrSpamFighter.Repo.Migrations.AddBlocklistLastError do
  use Ecto.Migration

  def change do
    alter table(:blocklists) do
      add :last_error, :text
    end
  end
end
