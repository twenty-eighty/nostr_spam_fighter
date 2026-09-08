defmodule NostrSpamFighter.Moderation.Classification do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "classifications" do
    field :event_id, :string
    field :status, :string

    belongs_to :scan, NostrSpamFighter.Moderation.Scan
    belongs_to :category, NostrSpamFighter.Policy.Category
    timestamps(type: :utc_datetime)
  end

  def changeset(classification, attrs) do
    classification
    |> cast(attrs, [:scan_id, :event_id, :category_id, :status])
    |> validate_required([:scan_id, :event_id, :category_id, :status])
    |> unique_constraint([:scan_id, :category_id])
  end
end
