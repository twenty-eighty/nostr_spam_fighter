defmodule NostrSpamFighter.Accounts.ApiKey do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @scopes ~w(articles:moderation:read)

  schema "api_keys" do
    field :name, :string
    field :key_prefix, :string
    field :secret_hash, :string
    field :scopes, {:array, :string}, default: []
    field :enabled, :boolean, default: true
    field :expires_at, :utc_datetime
    field :last_used_at, :utc_datetime
    field :last_used_ip, :string
    field :revoked_at, :utc_datetime
    field :plaintext, :string, virtual: true

    belongs_to :created_by_admin, NostrSpamFighter.Accounts.Admin
    timestamps(type: :utc_datetime)
  end

  def changeset(key, attrs) do
    key
    |> cast(attrs, [
      :name,
      :key_prefix,
      :secret_hash,
      :scopes,
      :enabled,
      :expires_at,
      :last_used_at,
      :last_used_ip,
      :created_by_admin_id,
      :revoked_at
    ])
    |> validate_required([:name, :key_prefix, :secret_hash, :scopes])
    |> validate_subset(:scopes, @scopes)
  end

  def scopes, do: @scopes
end
