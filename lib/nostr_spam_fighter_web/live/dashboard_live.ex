defmodule NostrSpamFighterWeb.DashboardLive do
  use NostrSpamFighterWeb, :live_view

  alias NostrSpamFighter.{Catalog, Ops}
  alias NostrSpamFighter.Policy.Cache

  @tick_ms 2_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NostrSpamFighter.PubSub, "events")
      Phoenix.PubSub.subscribe(NostrSpamFighter.PubSub, "scans")
      Phoenix.PubSub.subscribe(NostrSpamFighter.PubSub, "relays")
      Phoenix.PubSub.subscribe(NostrSpamFighter.PubSub, "blocklists")
      Phoenix.PubSub.subscribe(NostrSpamFighter.PubSub, "rescans")
      Process.send_after(self(), :tick, @tick_ms)
    end

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:download_progress, %{})
     |> assign(:refresh_pending, false)
     |> assign_snapshot()}
  end

  @impl true
  def handle_info(:tick, socket) do
    if connected?(socket), do: Process.send_after(self(), :tick, @tick_ms)
    {:noreply, assign_snapshot(socket)}
  end

  def handle_info(:refresh, socket) do
    {:noreply,
     socket
     |> NostrSpamFighterWeb.LiveRefresh.done()
     |> assign_snapshot()}
  end

  def handle_info({:blocklist_download_progress, id, progress}, socket) do
    {:noreply,
     socket
     |> assign(:download_progress, %{to_string(id) => progress})
     |> assign_snapshot()}
  end

  def handle_info(_, socket), do: {:noreply, NostrSpamFighterWeb.LiveRefresh.schedule(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 class="text-3xl font-semibold">Operations</h1>
          <p class="mt-1 opacity-70">Ingest, scans, and policy generation {@generation}.</p>
        </div>
        <p
          id="activity-live"
          class="inline-flex items-center gap-2 text-xs font-medium uppercase tracking-[0.2em] opacity-70"
        >
          <span class="relative flex size-2">
            <span class="absolute inline-flex size-2 animate-ping rounded-full bg-emerald-400 opacity-60"></span>
            <span class="relative inline-flex size-2 rounded-full bg-emerald-500"></span>
          </span>
          Live
        </p>
      </div>

      <section
        id="server-activity"
        class="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm"
      >
        <div class="flex items-center justify-between gap-4">
          <h2 class="text-sm font-semibold uppercase tracking-[0.18em] opacity-70">Now</h2>
          <p :if={@activity.queued_label} id="activity-queued" class="text-sm opacity-70">
            {@activity.queued_label}
          </p>
        </div>

        <div
          :if={@activity.items == [] and is_nil(@activity.queued_label)}
          id="activity-idle"
          class="mt-5 flex items-center gap-3 rounded-xl bg-base-200/70 px-4 py-5"
        >
          <.icon name="hero-pause-circle" class="size-5 opacity-50" />
          <div>
            <p class="font-medium">Idle</p>
            <p class="text-sm opacity-70">Waiting for new events.</p>
          </div>
        </div>

        <div
          :if={@activity.items == [] and @activity.queued_label}
          id="activity-waiting"
          class="mt-5 flex items-center gap-3 rounded-xl bg-amber-500/10 px-4 py-5"
        >
          <.icon name="hero-clock" class="size-5 text-amber-700 dark:text-amber-200" />
          <div>
            <p class="font-medium">Queued</p>
            <p class="text-sm opacity-70">{@activity.queued_label}</p>
          </div>
        </div>

        <ul :if={@activity.items != []} id="activity-items" class="mt-4 divide-y divide-base-300/70">
          <li
            :for={item <- @activity.items}
            id={"activity-#{item.id}"}
            class="flex items-start gap-3 py-3 first:pt-0 last:pb-0"
          >
            <span class={[
              "mt-0.5 inline-flex size-8 shrink-0 items-center justify-center rounded-full",
              item_tone(item.kind)
            ]}>
              <.icon name={item_icon(item.kind)} class={["size-4", item_spin(item.kind)]} />
            </span>
            <div class="min-w-0">
              <%= cond do %>
                <% item.event_id -> %>
                  <.link navigate={~p"/events/#{item.event_id}"} class="font-medium hover:underline">
                    {item.title}
                  </.link>
                <% item.blocklist_id -> %>
                  <.link
                    navigate={~p"/blocklists/#{item.blocklist_id}"}
                    class="font-medium hover:underline"
                  >
                    {item.title}
                  </.link>
                <% true -> %>
                  <p class="font-medium">{item.title}</p>
              <% end %>
              <p :if={item.detail} class="mt-0.5 text-sm tabular-nums opacity-70">{item.detail}</p>
            </div>
          </li>
        </ul>
      </section>

      <div class="grid grid-cols-2 gap-6 md:grid-cols-4">
        <div>
          <p class="text-sm uppercase tracking-wide">Events</p>
          <p class="text-3xl">{@stats.events}</p>
        </div>
        <div>
          <p class="text-sm uppercase tracking-wide">Scans</p>
          <p class="text-3xl">{@stats.scans}</p>
        </div>
        <div>
          <p class="text-sm uppercase tracking-wide">Matched</p>
          <p class="text-3xl">{@stats.matched}</p>
        </div>
        <div>
          <p class="text-sm uppercase tracking-wide">Matches</p>
          <p class="text-3xl">{@stats.matches}</p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp assign_snapshot(socket) do
    socket
    |> assign(:stats, Catalog.dashboard_stats())
    |> assign(:generation, Cache.generation())
    |> assign(:activity, Ops.snapshot(progress: socket.assigns.download_progress))
  end

  defp item_icon(:ingest), do: "hero-signal"
  defp item_icon(:scan), do: "hero-magnifying-glass"
  defp item_icon(:blocklist), do: "hero-shield-exclamation"
  defp item_icon(:publish), do: "hero-paper-airplane"
  defp item_icon(:withdraw), do: "hero-arrow-uturn-left"
  defp item_icon(:rescan), do: "hero-arrow-path"
  defp item_icon(_), do: "hero-cog-6-tooth"

  defp item_tone(:ingest), do: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-200"
  defp item_tone(:scan), do: "bg-sky-500/15 text-sky-700 dark:text-sky-200"
  defp item_tone(:blocklist), do: "bg-violet-500/15 text-violet-700 dark:text-violet-200"
  defp item_tone(:publish), do: "bg-amber-500/15 text-amber-800 dark:text-amber-200"
  defp item_tone(:withdraw), do: "bg-rose-500/15 text-rose-700 dark:text-rose-200"
  defp item_tone(_), do: "bg-base-300 text-base-content"

  defp item_spin(kind) when kind in [:scan, :blocklist, :rescan, :job],
    do: "motion-safe:animate-spin"

  defp item_spin(_), do: nil
end
