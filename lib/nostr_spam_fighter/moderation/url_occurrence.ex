defmodule NostrSpamFighter.Moderation.UrlOccurrence do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "url_occurrences" do
    field :original_url, :string
    field :normalized_url, :string
    field :hostname, :string
    field :source_type, :string
    field :source_location, :string

    belongs_to :scan, NostrSpamFighter.Moderation.Scan
    has_one :resolution, NostrSpamFighter.Moderation.UrlResolution
    timestamps(type: :utc_datetime)
  end

  def changeset(occ, attrs) do
    occ
    |> cast(attrs, [
      :scan_id,
      :original_url,
      :normalized_url,
      :hostname,
      :source_type,
      :source_location
    ])
    |> validate_required([:scan_id, :original_url, :normalized_url, :source_type])
  end
end
