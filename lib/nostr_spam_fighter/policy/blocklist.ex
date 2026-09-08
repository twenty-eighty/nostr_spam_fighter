defmodule NostrSpamFighter.Policy.Blocklist do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @source_types ~w(remote manual)
  @formats ~w(domains hosts urls)
  @refresh_statuses ~w(idle queued downloading importing ok failed rejected)

  schema "blocklists" do
    field :name, :string
    field :description, :string
    field :source_type, :string
    field :source_url, :string
    field :format, :string
    field :enabled, :boolean, default: true
    field :refresh_interval_s, :integer, default: 86_400
    field :last_attempt_at, :utc_datetime
    field :last_success_at, :utc_datetime
    field :next_refresh_at, :utc_datetime
    field :etag, :string
    field :last_modified, :string
    field :last_error, :string
    field :refresh_status, :string, default: "idle"

    belongs_to :category, NostrSpamFighter.Policy.Category
    belongs_to :active_version, NostrSpamFighter.Policy.BlocklistVersion
    has_many :versions, NostrSpamFighter.Policy.BlocklistVersion
    timestamps(type: :utc_datetime)
  end

  def changeset(blocklist, attrs) do
    blocklist
    |> cast(attrs, [
      :category_id,
      :name,
      :description,
      :source_type,
      :source_url,
      :format,
      :enabled,
      :refresh_interval_s,
      :last_attempt_at,
      :last_success_at,
      :next_refresh_at,
      :etag,
      :last_modified,
      :last_error,
      :refresh_status,
      :active_version_id
    ])
    |> update_change(:name, &trim_or_nil/1)
    |> update_change(:source_url, &trim_or_nil/1)
    |> validate_required([:category_id, :name, :source_type, :format])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_inclusion(:format, @formats)
    |> validate_inclusion(:refresh_status, @refresh_statuses)
    |> validate_number(:refresh_interval_s, greater_than: 0)
    |> maybe_require_source_url()
    |> unique_constraint(:name,
      name: :blocklists_category_id_name_index,
      message: "already exists for this category"
    )
    |> unique_constraint(:source_url,
      name: :blocklists_source_url_index,
      message: "already added"
    )
  end

  def refreshing?(%__MODULE__{refresh_status: status})
      when status in ~w(queued downloading importing),
      do: true

  def refreshing?(_), do: false

  def downloading?(%__MODULE__{refresh_status: status})
      when status in ~w(downloading importing),
      do: true

  def downloading?(_), do: false

  def refresh_label(%__MODULE__{refresh_status: "queued"}), do: "Queued"
  def refresh_label(%__MODULE__{refresh_status: "downloading"}), do: "Downloading"
  def refresh_label(%__MODULE__{refresh_status: "importing"}), do: "Importing"
  def refresh_label(%__MODULE__{refresh_status: "failed"}), do: "Failed"
  def refresh_label(%__MODULE__{refresh_status: "rejected"}), do: "Rejected"
  def refresh_label(_), do: nil

  def show_refresh_error?(%__MODULE__{last_error: error, refresh_status: status})
      when is_binary(error) and status not in ~w(downloading importing),
      do: true

  def show_refresh_error?(_), do: false

  def skip_auto_queue?(%__MODULE__{refresh_status: status}) when status in ~w(failed rejected),
    do: true

  def skip_auto_queue?(%__MODULE__{last_error: error}) when is_binary(error), do: true
  def skip_auto_queue?(_), do: false

  defp trim_or_nil(nil), do: nil

  defp trim_or_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp maybe_require_source_url(changeset) do
    if get_field(changeset, :source_type) == "remote" do
      validate_required(changeset, [:source_url])
    else
      changeset
    end
  end
end
