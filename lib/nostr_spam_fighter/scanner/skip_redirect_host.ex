defmodule NostrSpamFighter.Scanner.SkipRedirectHost do
  use Ecto.Schema
  import Ecto.Changeset

  alias NostrSpamFighter.Policy.Normalizer

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "skip_redirect_hosts" do
    field :host, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:host])
    |> update_change(:host, &trim/1)
    |> validate_required([:host])
    |> normalize_host()
    |> unique_constraint(:host)
  end

  def parse(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        {:error, :invalid_host}

      String.contains?(value, "://") ->
        host_from_url(value)

      true ->
        Normalizer.normalize_host(value)
    end
  end

  def parse(_), do: {:error, :invalid_host}

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  defp normalize_host(changeset) do
    case get_change(changeset, :host) do
      host when is_binary(host) ->
        case parse(host) do
          {:ok, normalized} -> put_change(changeset, :host, normalized)
          {:error, _} -> add_error(changeset, :host, "is not a valid hostname")
        end

      _ ->
        changeset
    end
  end

  defp host_from_url(value) do
    with {:ok, url} <- Normalizer.normalize_url(value),
         host when is_binary(host) <- Normalizer.hostname_from_url(url) do
      {:ok, host}
    else
      _ -> {:error, :invalid_host}
    end
  end
end
