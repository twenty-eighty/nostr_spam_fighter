defmodule NostrSpamFighterWeb.EventLive.Show do
  use NostrSpamFighterWeb, :live_view
  alias NostrSpamFighter.Catalog
  alias NostrSpamFighter.Jobs.ScanEventWorker

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Event",
       event: Catalog.get_event!(id),
       scan: Catalog.latest_scan(id)
     )}
  end

  @impl true
  def handle_event("rescan", _, socket) do
    %{event_id: socket.assigns.event.event_id} |> ScanEventWorker.new() |> Oban.insert()
    {:noreply, put_flash(socket, :info, "Rescan queued")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-3xl font-semibold">Event {String.slice(@event.event_id, 0, 16)}</h1>
      <p>kind {@event.kind} · {@event.article_address}</p>
      <p>relays: {Enum.map_join(@event.relays, ", ", & &1.relay_url)}</p>
      <button class="btn btn-sm mt-4" phx-click="rescan">Rescan</button>
      <div :if={@scan} class="mt-8 space-y-4">
        <p>
          Scan {@scan.status} · policy {@scan.policy_generation} · scanner {@scan.scanner_version}
        </p>
        <div :for={occ <- @scan.url_occurrences} class="border-t border-base-300 pt-3">
          <p class="font-mono text-sm">{occ.normalized_url}</p>
          <p class="text-sm opacity-70">
            {occ.source_type} · {occ.resolution && occ.resolution.status}
          </p>
          <details :if={occ.resolution} class="mt-2">
            <summary>Redirect hops</summary>
            <p :for={hop <- occ.resolution.redirect_hops} class="font-mono text-xs">
              {hop.hop_index}: {hop.url} ({hop.http_status}) {hop.resolved_ip}
            </p>
          </details>
        </div>
        <div :for={match <- @scan.matches}>
          <p>
            Match {match.category && match.category.slug} via {match.blocklist && match.blocklist.name}
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
