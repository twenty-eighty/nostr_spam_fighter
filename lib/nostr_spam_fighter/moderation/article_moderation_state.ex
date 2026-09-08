defmodule NostrSpamFighter.Moderation.ArticleModerationState do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "article_moderation_states" do
    field :event_id, :string
    field :status, :string
    field :blacklisted, :boolean
    field :policy_generation, :integer

    belongs_to :article_address, NostrSpamFighter.Moderation.ArticleAddress
    belongs_to :scan, NostrSpamFighter.Moderation.Scan
    has_many :categories, NostrSpamFighter.Moderation.ArticleModerationCategory
    timestamps(type: :utc_datetime)
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [
      :article_address_id,
      :event_id,
      :scan_id,
      :status,
      :blacklisted,
      :policy_generation
    ])
    |> validate_required([:article_address_id, :status])
  end
end
