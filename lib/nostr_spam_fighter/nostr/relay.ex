defmodule NostrSpamFighter.Nostr.Relay do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "nostr_relays" do
    field :url, :string
    field :enabled, :boolean, default: true
    field :read_enabled, :boolean, default: true
    field :write_enabled, :boolean, default: false
    timestamps(type: :utc_datetime)
  end

  def changeset(relay, attrs) do
    relay
    |> cast(attrs, [:url, :enabled, :read_enabled, :write_enabled])
    |> validate_required([:url])
    |> validate_format(:url, ~r/^wss?:\/\//)
    |> unique_constraint(:url)
  end
end
