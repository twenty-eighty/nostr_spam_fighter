defmodule NostrSpamFighter.Moderation.PublishedLabel do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "published_labels" do
    field :event_id, :string
    field :label_event_id, :string
    field :signed_event, :map
    field :status, :string, default: "pending"
    field :withdrawn_at, :utc_datetime

    belongs_to :category, NostrSpamFighter.Policy.Category
    has_many :deliveries, NostrSpamFighter.Moderation.PublishedLabelDelivery
    timestamps(type: :utc_datetime)
  end

  def changeset(label, attrs) do
    label
    |> cast(attrs, [
      :event_id,
      :category_id,
      :label_event_id,
      :signed_event,
      :status,
      :withdrawn_at
    ])
    |> validate_required([:event_id, :category_id, :label_event_id, :signed_event, :status])
    |> unique_constraint([:event_id, :category_id])
  end
end
