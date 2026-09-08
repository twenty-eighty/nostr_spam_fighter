defmodule NostrSpamFighter.Moderation.PublishedLabelDelivery do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "published_label_deliveries" do
    field :relay_url, :string
    field :status, :string
    field :error, :string
    field :attempted_at, :utc_datetime

    belongs_to :published_label, NostrSpamFighter.Moderation.PublishedLabel
    timestamps(type: :utc_datetime)
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [:published_label_id, :relay_url, :status, :error, :attempted_at])
    |> validate_required([:published_label_id, :relay_url, :status])
  end
end
