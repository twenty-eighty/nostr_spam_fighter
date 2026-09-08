defmodule NostrSpamFighter.Moderation.Match do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "matches" do
    field :matched_url, :string
    field :matched_hostname, :string
    field :match_type, :string
    field :event_id, :string, virtual: true

    belongs_to :scan, NostrSpamFighter.Moderation.Scan
    belongs_to :url_occurrence, NostrSpamFighter.Moderation.UrlOccurrence
    belongs_to :redirect_hop, NostrSpamFighter.Moderation.RedirectHop
    belongs_to :category, NostrSpamFighter.Policy.Category
    belongs_to :blocklist, NostrSpamFighter.Policy.Blocklist
    belongs_to :blocklist_version, NostrSpamFighter.Policy.BlocklistVersion
    belongs_to :blocklist_entry, NostrSpamFighter.Policy.BlocklistEntry
    timestamps(type: :utc_datetime)
  end

  def changeset(match, attrs) do
    match
    |> cast(attrs, [
      :scan_id,
      :url_occurrence_id,
      :redirect_hop_id,
      :category_id,
      :blocklist_id,
      :blocklist_version_id,
      :blocklist_entry_id,
      :matched_url,
      :matched_hostname,
      :match_type
    ])
    |> validate_required([
      :scan_id,
      :category_id,
      :blocklist_id,
      :blocklist_version_id,
      :blocklist_entry_id,
      :match_type
    ])
  end
end
