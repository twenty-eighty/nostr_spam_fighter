defmodule NostrSpamFighterWeb.HealthController do
  use NostrSpamFighterWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def ready(conn, _params) do
    db? =
      case NostrSpamFighter.Repo.query("SELECT 1") do
        {:ok, _} -> true
        _ -> false
      end

    cache? = NostrSpamFighter.Policy.Cache.ready?()

    if db? and cache? do
      json(conn, %{status: "ready", database: true, policy_cache: true})
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{status: "unavailable", database: db?, policy_cache: cache?})
    end
  end
end
