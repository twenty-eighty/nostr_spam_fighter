defmodule NostrSpamFighter.Repo.Migrations.WidenNostrEventDTagColumns do
  use Ecto.Migration

  def change do
    alter table(:nostr_events) do
      modify :d_tag, :text, from: :string
      modify :article_address, :text, from: :string
    end

    alter table(:article_addresses) do
      modify :d_tag, :text, from: :string, null: false
      modify :address, :text, from: :string, null: false
    end
  end
end
