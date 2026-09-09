defmodule NostrSpamFighterWeb.TargetModerationController do
  use NostrSpamFighterWeb, :controller

  alias NostrSpamFighter.Moderation.TargetState

  def domain(conn, %{"domain" => domain}) do
    case TargetState.lookup_domain(domain) do
      {:ok, result} ->
        respond(conn, result)

      {:error, :invalid_domain} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid domain"})
    end
  end

  def url(conn, params) do
    url = params["url"]

    cond do
      not is_binary(url) or String.trim(url) == "" ->
        conn |> put_status(:bad_request) |> json(%{error: "url required"})

      true ->
        case TargetState.lookup_url(url) do
          {:ok, result} ->
            respond(conn, result)

          {:error, :invalid_url} ->
            conn |> put_status(:bad_request) |> json(%{error: "invalid url"})
        end
    end
  end

  defp respond(conn, result) do
    etag = etag(result)

    if get_req_header(conn, "if-none-match") == [etag] do
      conn |> put_resp_header("etag", etag) |> send_resp(304, "")
    else
      conn |> put_resp_header("etag", etag) |> json(public(result))
    end
  end

  defp public(result) do
    result
    |> Map.take([
      :domain,
      :registrable_domain,
      :url,
      :final_url,
      :final_domain,
      :redirect_count,
      :resolution_status,
      :blacklisted,
      :status,
      :categories,
      :lists,
      :scanned_at,
      :policy_generation
    ])
    |> Map.update(:lists, [], &public_lists/1)
  end

  defp public_lists(lists) when is_list(lists) do
    Enum.map(lists, fn list ->
      Map.take(list, [:id, :name, :category_slug, :category_name, :blocks_serving])
    end)
  end

  defp public_lists(_), do: []

  defp etag(result) do
    material =
      Enum.join(
        [
          result[:registrable_domain],
          result[:final_url],
          result[:policy_generation],
          result[:resolution_status],
          Enum.join(result[:categories] || [], ","),
          result[:lists] |> List.wrap() |> Enum.map(& &1[:id]) |> Enum.join(",")
        ],
        ":"
      )

    ~s("#{Base.encode16(:crypto.hash(:sha256, material), case: :lower)}")
  end
end
