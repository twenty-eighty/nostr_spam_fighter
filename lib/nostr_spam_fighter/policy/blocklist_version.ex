defmodule NostrSpamFighter.Policy.BlocklistVersion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "blocklist_versions" do
    field :status, :string
    field :checksum, :string
    field :entry_count, :integer, default: 0
    field :fetched_at, :utc_datetime
    field :validated_at, :utc_datetime
    field :activated_at, :utc_datetime
    field :error, :string

    belongs_to :blocklist, NostrSpamFighter.Policy.Blocklist
    has_many :entries, NostrSpamFighter.Policy.BlocklistEntry
    timestamps(type: :utc_datetime)
  end

  def changeset(version, attrs) do
    version
    |> cast(attrs, [
      :blocklist_id,
      :status,
      :checksum,
      :entry_count,
      :fetched_at,
      :validated_at,
      :activated_at,
      :error
    ])
    |> validate_required([:blocklist_id, :status])
    |> validate_inclusion(:status, ~w(pending validated active failed superseded))
  end
end
