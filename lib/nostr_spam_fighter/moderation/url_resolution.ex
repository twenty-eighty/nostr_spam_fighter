defmodule NostrSpamFighter.Moderation.UrlResolution do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "url_resolutions" do
    field :status, :string
    field :final_url, :string
    field :final_hostname, :string
    field :http_status, :integer
    field :redirect_count, :integer, default: 0
    field :duration_ms, :integer
    field :error, :string

    belongs_to :url_occurrence, NostrSpamFighter.Moderation.UrlOccurrence
    has_many :redirect_hops, NostrSpamFighter.Moderation.RedirectHop
    timestamps(type: :utc_datetime)
  end

  def changeset(res, attrs) do
    res
    |> cast(attrs, [
      :url_occurrence_id,
      :status,
      :final_url,
      :final_hostname,
      :http_status,
      :redirect_count,
      :duration_ms,
      :error
    ])
    |> validate_required([:url_occurrence_id, :status])
  end
end
