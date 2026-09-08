defmodule NostrSpamFighterWeb.LiveRefresh do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]

  def schedule(socket, message \\ :refresh, delay_ms \\ 400) do
    if socket.assigns[:refresh_pending] do
      socket
    else
      Process.send_after(self(), message, delay_ms)
      assign(socket, :refresh_pending, true)
    end
  end

  def done(socket), do: assign(socket, :refresh_pending, false)
end
