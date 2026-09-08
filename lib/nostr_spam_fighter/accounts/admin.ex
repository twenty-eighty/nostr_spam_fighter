defmodule NostrSpamFighter.Accounts.Admin do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "admins" do
    field :pubkey, :string
    field :name, :string
    field :enabled, :boolean, default: true
    field :last_login_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(admin, attrs) do
    admin
    |> cast(attrs, [:pubkey, :name, :enabled, :last_login_at])
    |> update_change(:pubkey, &String.downcase/1)
    |> validate_required([:pubkey])
    |> validate_format(:pubkey, ~r/^[0-9a-f]{64}$/)
    |> unique_constraint(:pubkey)
  end
end
