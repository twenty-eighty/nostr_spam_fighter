defmodule NostrSpamFighterWeb.RelayLive.Index do
  use NostrSpamFighterWeb, :live_view
  alias NostrSpamFighter.Relays
  alias NostrSpamFighter.Nostr.{Relay, RelayIngest}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(NostrSpamFighter.PubSub, "relays")

    {:ok,
     assign(socket,
       page_title: "Relays",
       relays: Relays.list_relays(),
       ingest: RelayIngest.status(),
       form: to_form(Relays.change_relay(%Relay{})),
       refresh_pending: false
     )}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply,
     socket
     |> NostrSpamFighterWeb.LiveRefresh.done()
     |> assign(:relays, Relays.list_relays())
     |> assign(:ingest, RelayIngest.status())}
  end

  def handle_info(_, socket), do: {:noreply, NostrSpamFighterWeb.LiveRefresh.schedule(socket)}

  @impl true
  def handle_event("save", %{"relay" => params}, socket) do
    case Relays.create_relay(params) do
      {:ok, _} -> {:noreply, assign(socket, relays: Relays.list_relays())}
      {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("toggle", %{"id" => id, "field" => field}, socket) do
    relay = Relays.get_relay!(id)

    {:ok, _} =
      Relays.update_relay(relay, %{field => !Map.get(relay, String.to_existing_atom(field))})

    {:noreply, assign(socket, relays: Relays.list_relays())}
  end

  def handle_event("start_ingest", _, socket) do
    RelayIngest.start()
    {:noreply, assign(socket, ingest: RelayIngest.status())}
  end

  def handle_event("stop_ingest", _, socket) do
    RelayIngest.stop()
    {:noreply, assign(socket, ingest: RelayIngest.status())}
  end

  def handle_event("reconnect", _, socket) do
    RelayIngest.reconnect()

    {:noreply,
     assign(socket, ingest: RelayIngest.status()) |> put_flash(:info, "Reconnect requested")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-3xl font-semibold">Relays</h1>
      <p id="ingest-status" class="mt-4">
        Event loading: {ingest_label(@ingest)}
      </p>
      <div class="mt-2 flex gap-2">
        <button id="ingest-start" class="btn btn-sm" phx-click="start_ingest">Start</button>
        <button id="ingest-stop" class="btn btn-sm" phx-click="stop_ingest">Stop</button>
        <button id="ingest-reconnect" class="btn btn-sm" phx-click="reconnect">Reconnect</button>
      </div>
      <ul class="mt-6 space-y-2">
        <li :for={relay <- @relays}>
          {relay.url} enabled={to_string(relay.enabled)} read={to_string(relay.read_enabled)} write={to_string(
            relay.write_enabled
          )}
          <button
            class="btn btn-xs"
            phx-click="toggle"
            phx-value-id={relay.id}
            phx-value-field="enabled"
          >toggle</button>
        </li>
      </ul>
      <.form for={@form} phx-submit="save" class="mt-8 space-y-3 max-w-md">
        <.input field={@form[:url]} label="URL" />
        <.input field={@form[:read_enabled]} type="checkbox" label="Read" />
        <.input field={@form[:write_enabled]} type="checkbox" label="Write" />
        <button class="btn btn-primary">Add</button>
      </.form>
    </Layouts.app>
    """
  end

  defp ingest_label(%{pending: true}), do: "starting"
  defp ingest_label(%{running: true}), do: "running"
  defp ingest_label(_), do: "stopped"
end
