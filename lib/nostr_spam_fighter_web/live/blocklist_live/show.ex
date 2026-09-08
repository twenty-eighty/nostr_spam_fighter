defmodule NostrSpamFighterWeb.BlocklistLive.Show do
  use NostrSpamFighterWeb, :live_view
  import NostrSpamFighterWeb.BlocklistComponents
  alias NostrSpamFighter.Policy
  alias NostrSpamFighter.Policy.Blocklist
  alias NostrSpamFighter.Jobs.{RefreshBlocklistWorker, RescanEventsWorker}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NostrSpamFighter.PubSub, "blocklists")
    end

    {:ok, assign_blocklist(socket, id)}
  end

  @impl true
  def handle_info({:blocklist_download_progress, id, progress}, socket) do
    list = socket.assigns.blocklist

    if list.refresh_status in ~w(downloading importing) and to_string(list.id) == to_string(id) do
      {:noreply, assign(socket, :download_progress, %{to_string(id) => progress})}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:blocklist_refreshed, id}, socket) do
    if to_string(socket.assigns.blocklist.id) == to_string(id) do
      socket = assign_blocklist(socket, id)
      list = socket.assigns.blocklist

      socket =
        if list.refresh_status in ~w(downloading importing) do
          socket
        else
          assign(socket, :download_progress, %{})
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("save", %{"blocklist" => params}, socket) do
    was_enabled = socket.assigns.blocklist.enabled

    case Policy.update_blocklist(socket.assigns.blocklist, params) do
      {:ok, list} ->
        flash =
          cond do
            was_enabled and not list.enabled ->
              "Disabled — removed from policy cache / matching"

            not was_enabled and list.enabled ->
              "Enabled — reloaded into policy cache"

            true ->
              "Saved"
          end

        {:noreply,
         socket
         |> assign(blocklist: list, form: to_form(Policy.change_blocklist(list)))
         |> put_flash(:info, flash)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("import", %{"body" => body}, socket) do
    case Policy.import_manual_entries(socket.assigns.blocklist, body) do
      {:ok, _} ->
        {:noreply, assign_blocklist(socket, socket.assigns.blocklist.id)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Import failed")}
    end
  end

  def handle_event("refresh", _, socket) do
    case RefreshBlocklistWorker.enqueue(socket.assigns.blocklist.id, force: true) do
      :ok ->
        {:noreply,
         socket
         |> assign_blocklist(socket.assigns.blocklist.id)
         |> put_flash(:info, "Refresh queued")}

      {:error, :disabled} ->
        {:noreply, put_flash(socket, :error, "Enable the blocklist before refreshing")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not queue refresh")}
    end
  end

  def handle_event("rescan", %{"mode" => mode}, socket) do
    %{mode: mode} |> RescanEventsWorker.new() |> Oban.insert()
    {:noreply, put_flash(socket, :info, "Rescan queued (#{mode})")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-3xl font-semibold">{@blocklist.name}</h1>
      <p id="blocklist-stats" class="mt-2 opacity-70">
        {entry_count(@blocklist)} entries · last read {format_read_at(@blocklist)} · {if @blocklist.enabled,
          do: "enabled",
          else: "disabled"}
      </p>
      <p :if={not @blocklist.enabled} class="mt-2 text-sm opacity-70">
        Disabled lists are kept in the database but excluded from matching and the in-memory policy cache.
      </p>
      <div class="mt-2">
        <.refresh_status
          list={@blocklist}
          id="blocklist-progress"
          error_id="blocklist-error"
          progress={
            if(@blocklist.refresh_status in ~w(downloading importing),
              do:
                Map.get(@download_progress, @blocklist.id) ||
                  Map.get(@download_progress, to_string(@blocklist.id))
            )
          }
        />
      </div>
      <.form
        for={@form}
        id="blocklist-settings-form"
        phx-submit="save"
        class="mt-4 space-y-3 max-w-md"
      >
        <.input field={@form[:enabled]} type="checkbox" label="Enabled (include in policy cache)" />
        <.input field={@form[:source_url]} label="Source URL" />
        <button class="btn btn-primary btn-sm">Save</button>
      </.form>
      <div class="mt-4 flex gap-2">
        <button
          id="refresh-blocklist"
          class="btn btn-sm"
          phx-click="refresh"
          disabled={Blocklist.downloading?(@blocklist) or not @blocklist.enabled}
        >
          Refresh now
        </button>
        <button class="btn btn-sm" phx-click="rescan" phx-value-mode="new">New events only</button>
        <button class="btn btn-sm" phx-click="rescan" phx-value-mode="existing">Rescan existing</button>
      </div>
      <form phx-submit="import" class="mt-6">
        <textarea
          name="body"
          class="textarea w-full"
          rows="6"
          placeholder="one domain/host/url per line"
        ></textarea>
        <button class="btn btn-primary mt-2">Import version</button>
      </form>
      <h2 class="mt-8 text-xl">Versions</h2>
      <ul>
        <li :for={v <- @versions}>{v.status} · {v.entry_count} · {v.checksum} · {v.error}</li>
      </ul>
      <h2 class="mt-8 text-xl">Entries</h2>
      <ul>
        <li :for={e <- @entries} class="font-mono text-sm">{e.rule_type} {e.normalized_value}</li>
      </ul>
    </Layouts.app>
    """
  end

  defp assign_blocklist(socket, id) do
    list = Policy.get_blocklist_for_ui!(id)
    versions = Policy.list_versions(list)
    active = list.active_version

    socket
    |> assign_new(:download_progress, fn -> %{} end)
    |> assign(
      page_title: list.name,
      blocklist: list,
      versions: versions,
      entries: if(active, do: Policy.list_entries(active), else: []),
      form: to_form(Policy.change_blocklist(list))
    )
  end

  defp entry_count(%{active_version: %{entry_count: count}}) when is_integer(count), do: count
  defp entry_count(_), do: 0

  defp format_read_at(%{last_success_at: %DateTime{} = at}), do: format_time(at)
  defp format_read_at(%{last_attempt_at: %DateTime{} = at}), do: "#{format_time(at)} (failed)"
  defp format_read_at(_), do: "never"

  defp format_time(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
end
