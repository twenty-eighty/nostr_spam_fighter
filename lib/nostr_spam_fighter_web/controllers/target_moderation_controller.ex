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
    Map.take(result, [
      :domain,
      :registrable_domain,
      :url,
      :blacklisted,
      :status,
      :categories,
      :scanned_at,
      :policy_generation
    ])
  end

  defp etag(result) do
    material =
      "#{result[:registrable_domain]}:#{result[:policy_generation]}:#{Enum.join(result[:categories] || [], ",")}"

    ~s("#{Base.encode16(:crypto.hash(:sha256, material), case: :lower)}")
  end
end
