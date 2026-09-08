defmodule NostrSpamFighter.Moderation.Scan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "scans" do
    field :event_id, :string
    field :policy_generation, :integer
    field :status, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :urls_discovered, :integer, default: 0
    field :urls_resolved, :integer, default: 0
    field :redirects_followed, :integer, default: 0
    field :matches_found, :integer, default: 0
    field :error, :string
    field :scanner_version, :string

    has_many :url_occurrences, NostrSpamFighter.Moderation.UrlOccurrence
    has_many :matches, NostrSpamFighter.Moderation.Match
    has_many :classifications, NostrSpamFighter.Moderation.Classification
    timestamps(type: :utc_datetime)
  end

  def changeset(scan, attrs) do
    scan
    |> cast(attrs, [
      :event_id,
      :policy_generation,
      :status,
      :started_at,
      :completed_at,
      :urls_discovered,
      :urls_resolved,
      :redirects_followed,
      :matches_found,
      :error,
      :scanner_version
    ])
    |> validate_required([:event_id, :policy_generation, :status, :scanner_version])
    |> validate_inclusion(:status, ~w(pending running clean matched partial failed))
  end
end
