defmodule NostrSpamFighter.Repo.Migrations.CreateSkipRedirectHosts do
  use Ecto.Migration

  def change do
    create table(:skip_redirect_hosts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :host, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:skip_redirect_hosts, [:host])
  end
end
