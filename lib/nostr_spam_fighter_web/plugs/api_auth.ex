defmodule NostrSpamFighterWeb.Plugs.ApiAuth do
  @moduledoc false
  import Plug.Conn
  alias NostrSpamFighter.Accounts
  alias NostrSpamFighter.Accounts.RateLimiter

  # Mix is not available in releases; bake env at compile time.
  @env Mix.env()

  def init(opts), do: opts

  def call(conn, opts) do
    scope = Keyword.get(opts, :scope, "articles:moderation:read")

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, key} <- Accounts.verify_api_key(token),
         true <- Accounts.has_scope?(key, scope) || {:error, :forbidden},
         :ok <- RateLimiter.check(key.id, batch_cost(conn)) do
      if @env != :test do
        Task.start(fn -> Accounts.touch_api_key(key, ip(conn)) end)
      end

      assign(conn, :api_key, key)
    else
      [] -> send_err(conn, 401, "missing api key")
      {:error, :forbidden} -> send_err(conn, 403, "insufficient scope")
      {:error, :rate_limited} -> send_err(conn, 429, "rate limited")
      {:error, _} -> send_err(conn, 401, "invalid api key")
    end
  end

  defp batch_cost(%{body_params: %{"naddrs" => list}}) when is_list(list),
    do: max(length(list), 1)

  defp batch_cost(_), do: 1

  defp ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  defp send_err(conn, status, message) do
    conn
    |> put_status(status)
    |> Phoenix.Controller.json(%{error: message})
    |> halt()
  end
end
