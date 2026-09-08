defmodule NostrSpamFighterWeb.SettingsLive do
  use NostrSpamFighterWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Settings",
       namespace: NostrSpamFighter.Policy.Namespace.content(),
       scanner: Application.get_env(:nostr_spam_fighter, :scanner_version),
       generation: NostrSpamFighter.Policy.Cache.generation()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-3xl font-semibold">Settings</h1>
      <p class="mt-4">NIP-32 namespace: <code>{@namespace}</code></p>
      <p>Scanner version: {@scanner}</p>
      <p>Policy generation: {@generation}</p>
    </Layouts.app>
    """
  end
end
