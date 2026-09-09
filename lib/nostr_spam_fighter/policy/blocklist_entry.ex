defmodule NostrSpamFighter.Policy.BlocklistEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @rule_types ~w(domain host url_prefix)

  schema "blocklist_entries" do
    field :rule_type, :string
    field :normalized_value, :string
    field :registrable_domain, :string

    belongs_to :blocklist_version, NostrSpamFighter.Policy.BlocklistVersion
    timestamps(type: :utc_datetime)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:blocklist_version_id, :rule_type, :normalized_value, :registrable_domain])
    |> validate_required([:blocklist_version_id, :rule_type, :normalized_value])
    |> validate_inclusion(:rule_type, @rule_types)
  end
end
