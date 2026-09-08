defmodule NostrSpamFighterWeb.AuthController do
  use NostrSpamFighterWeb, :controller

  alias NostrSpamFighter.Accounts
  alias NostrSpamFighter.Accounts.NostrAuth

  def login(conn, _params) do
    if Accounts.admin_auth_required?() do
      render(conn, :login)
    else
      redirect(conn, to: ~p"/dashboard")
    end
  end

  def create(conn, _params) do
    auth = get_req_header(conn, "authorization") |> List.first()
    url = url(conn, ~p"/auth/nostr")

    conn_info = %{
      method: "POST",
      url: url
    }

    case NostrAuth.verify(auth, conn_info) do
      {:ok, admin} ->
        Accounts.touch_login(admin)

        conn
        |> renew_session()
        |> put_session(:admin_id, admin.id)
        |> json(%{ok: true, redirect: ~p"/dashboard"})

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  def delete(conn, _params) do
    conn
    |> renew_session()
    |> redirect(to: ~p"/login")
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
