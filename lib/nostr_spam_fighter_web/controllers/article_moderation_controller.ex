defmodule NostrSpamFighterWeb.ArticleModerationController do
  use NostrSpamFighterWeb, :controller

  alias NostrSpamFighter.Moderation.ArticleState

  def show(conn, %{"naddr" => naddr}) do
    respond(conn, naddr)
  end

  def check(conn, %{"naddrs" => naddrs}) when is_list(naddrs) do
    limit = Application.get_env(:nostr_spam_fighter, :batch_moderation_limit, 500)

    if length(naddrs) > limit do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "batch too large", max: limit})
    else
      results = Enum.map(naddrs, &lookup/1)
      json(conn, %{results: results})
    end
  end

  def check(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "naddrs required"})
  end

  defp respond(conn, naddr) do
    case lookup(naddr) do
      %{error: :malformed_naddr} ->
        conn |> put_status(:bad_request) |> json(%{error: "malformed naddr"})

      %{error: :unsupported_kind} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "unsupported kind"})

      result ->
        etag = etag(result)

        if get_req_header(conn, "if-none-match") == [etag] do
          conn |> put_resp_header("etag", etag) |> send_resp(304, "")
        else
          conn |> put_resp_header("etag", etag) |> json(public(result))
        end
    end
  end

  defp lookup(naddr) do
    case ArticleState.lookup_by_naddr(naddr) do
      {:ok, result} -> result
      {:error, reason} -> %{naddr: naddr, error: reason}
    end
  end

  defp public(result) do
    Map.take(result, [
      :naddr,
      :address,
      :blacklisted,
      :status,
      :event_id,
      :event_created_at,
      :categories,
      :scanned_at,
      :policy_generation
    ])
  end

  defp etag(result) do
    material = "#{result[:event_id]}:#{result[:scan_id]}:#{result[:policy_generation]}"
    ~s("#{Base.encode16(:crypto.hash(:sha256, material), case: :lower)}")
  end
end
