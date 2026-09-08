defmodule NostrSpamFighter.Moderation.ArticleAddress do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "article_addresses" do
    field :kind, :integer
    field :pubkey, :string
    field :d_tag, :string
    field :address, :string
    field :current_event_id, :string
    field :current_event_created_at, :integer

    has_one :moderation_state, NostrSpamFighter.Moderation.ArticleModerationState
    timestamps(type: :utc_datetime)
  end

  def changeset(address, attrs) do
    address
    |> cast(attrs, [
      :kind,
      :pubkey,
      :d_tag,
      :address,
      :current_event_id,
      :current_event_created_at
    ])
    |> validate_required([:kind, :pubkey, :d_tag, :address])
    |> unique_constraint([:kind, :pubkey, :d_tag])
  end

  def canonical(kind, pubkey, d_tag), do: "#{kind}:#{pubkey}:#{d_tag}"
end
