defmodule NostrSpamFighterWeb.Hooks.RequireAdmin do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView
  alias NostrSpamFighter.Accounts
  alias NostrSpamFighter.Accounts.Admin
  alias NostrSpamFighter.Repo

  def on_mount(:default, _params, session, socket) do
    admin_id = session["admin_id"]

    case admin_id && Repo.get(Admin, admin_id) do
      %Admin{enabled: true} = admin ->
        {:cont, assign(socket, :current_admin, admin)}

      _ ->
        if Accounts.admin_auth_required?() do
          {:halt, redirect(socket, to: "/login")}
        else
          {:cont, assign(socket, :current_admin, nil)}
        end
    end
  end
end
