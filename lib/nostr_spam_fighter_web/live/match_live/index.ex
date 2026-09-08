defmodule NostrSpamFighterWeb.MatchLive.Index do
  use NostrSpamFighterWeb, :live_view
  alias NostrSpamFighter.Catalog

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Matches", matches: Catalog.list_matches())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-3xl font-semibold">Matches</h1>
      <ul class="mt-6 space-y-2">
        <li :for={match <- @matches}>
          {match.category && match.category.slug} · {match.matched_hostname} · {match.match_type}
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
