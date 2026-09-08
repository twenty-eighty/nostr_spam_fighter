defmodule NostrSpamFighter.Policy.Category do
  use Ecto.Schema
  import Ecto.Changeset

  @slug_regex ~r/^[a-z0-9][a-z0-9_-]*$/

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "content_categories" do
    field :slug, :string
    field :name, :string
    field :description, :string
    field :enabled, :boolean, default: true
    field :blocks_serving, :boolean, default: false

    has_many :blocklists, NostrSpamFighter.Policy.Blocklist
    timestamps(type: :utc_datetime)
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:slug, :name, :description, :enabled, :blocks_serving])
    |> validate_required([:slug, :name])
    |> validate_format(:slug, @slug_regex)
    |> unique_constraint(:slug)
  end

  def slug_locked_changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :description, :enabled, :blocks_serving])
    |> validate_required([:name])
  end
end
