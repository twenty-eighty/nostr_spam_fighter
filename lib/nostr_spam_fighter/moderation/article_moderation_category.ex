defmodule NostrSpamFighter.Moderation.ArticleModerationCategory do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "article_moderation_categories" do
    field :slug, :string
    belongs_to :article_moderation_state, NostrSpamFighter.Moderation.ArticleModerationState
    belongs_to :category, NostrSpamFighter.Policy.Category
  end
end
