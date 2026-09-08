defmodule NostrSpamFighter.Moderation.RedirectHop do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "redirect_hops" do
    field :hop_index, :integer
    field :url, :string
    field :hostname, :string
    field :resolved_ip, :string
    field :http_status, :integer
    field :location, :string
    field :duration_ms, :integer

    belongs_to :url_resolution, NostrSpamFighter.Moderation.UrlResolution
    timestamps(type: :utc_datetime)
  end

  def changeset(hop, attrs) do
    hop
    |> cast(attrs, [
      :url_resolution_id,
      :hop_index,
      :url,
      :hostname,
      :resolved_ip,
      :http_status,
      :location,
      :duration_ms
    ])
    |> validate_required([:url_resolution_id, :hop_index, :url])
  end
end
