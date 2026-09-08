defmodule NostrSpamFighter.Nostr.EventRelay do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :string

  schema "event_relays" do
    field :event_id, :string
    field :relay_url, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:event_id, :relay_url])
    |> validate_required([:event_id, :relay_url])
    |> unique_constraint([:event_id, :relay_url])
  end
end
