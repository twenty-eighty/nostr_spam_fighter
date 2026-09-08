defmodule NostrSpamFighterWeb.PageController do
  use NostrSpamFighterWeb, :controller

  def home(conn, _params) do
    if get_session(conn, :admin_id) || not NostrSpamFighter.Accounts.admin_auth_required?() do
      redirect(conn, to: ~p"/dashboard")
    else
      redirect(conn, to: ~p"/login")
    end
  end
end
