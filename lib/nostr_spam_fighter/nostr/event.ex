defmodule NostrSpamFighter.Nostr.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:event_id, :string, autogenerate: false}
  @foreign_key_type :binary_id

  schema "nostr_events" do
    field :kind, :integer
    field :pubkey, :string
    field :created_at, :integer
    field :d_tag, :string
    field :article_address, :string
    field :raw_event, :map
    field :first_seen_at, :utc_datetime
    field :last_seen_at, :utc_datetime

    has_many :relays, NostrSpamFighter.Nostr.EventRelay,
      foreign_key: :event_id,
      references: :event_id

    has_many :scans, NostrSpamFighter.Moderation.Scan,
      foreign_key: :event_id,
      references: :event_id
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :event_id,
      :kind,
      :pubkey,
      :created_at,
      :d_tag,
      :article_address,
      :raw_event,
      :first_seen_at,
      :last_seen_at
    ])
    |> validate_required([:event_id, :kind, :pubkey, :created_at, :raw_event])
  end
end
