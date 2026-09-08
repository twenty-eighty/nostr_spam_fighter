defmodule NostrSpamFighterWeb.EventLive.Index do
  use NostrSpamFighterWeb, :live_view
  alias NostrSpamFighter.Catalog

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(NostrSpamFighter.PubSub, "events")

    {:ok,
     assign(socket,
       page_title: "Events",
       events: Catalog.list_events(),
       refresh_pending: false
     )}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply,
     socket
     |> NostrSpamFighterWeb.LiveRefresh.done()
     |> assign(:events, Catalog.list_events())}
  end

  def handle_info(_, socket), do: {:noreply, NostrSpamFighterWeb.LiveRefresh.schedule(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-3xl font-semibold">Events</h1>
      <table class="table mt-6">
        <thead>
          <tr>
            <th>ID</th>
            <th>Kind</th>
            <th>Address</th>
            <th>Seen</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={event <- @events}>
            <td>
              <.link navigate={~p"/events/#{event.event_id}"} class="link">{String.slice(
                event.event_id,
                0,
                12
              )}</.link>
            </td>
            <td>{event.kind}</td>
            <td>{event.article_address}</td>
            <td>{event.last_seen_at}</td>
          </tr>
        </tbody>
      </table>
    </Layouts.app>
    """
  end
end
