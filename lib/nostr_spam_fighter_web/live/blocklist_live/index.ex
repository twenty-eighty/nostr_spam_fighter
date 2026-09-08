defmodule NostrSpamFighterWeb.BlocklistLive.Index do
  use NostrSpamFighterWeb, :live_view
  import NostrSpamFighterWeb.BlocklistComponents
  alias NostrSpamFighter.Policy
  alias NostrSpamFighter.Policy.{Blocklist, Category}
  alias NostrSpamFighter.Jobs.{RefreshBlocklistWorker, ScheduleBlocklistRefreshWorker}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NostrSpamFighter.PubSub, "blocklists")
    end

    {:ok,
     assign(socket,
       page_title: "Blocklists",
       blocklists: Policy.list_blocklists(),
       download_progress: %{},
       categories: Policy.ensure_default_categories(),
       form: to_form(Policy.change_blocklist(%Blocklist{})),
       category_form: to_form(Policy.change_category(%Category{}))
     )}
  end

  @impl true
  def handle_info({:blocklist_download_progress, id, progress}, socket) do
    {:noreply, assign(socket, :download_progress, keep_active_progress(socket, id, progress))}
  end

  def handle_info({:blocklist_refreshed, _id}, socket) do
    lists = Policy.list_blocklists()

    {:noreply,
     socket
     |> assign(:blocklists, lists)
     |> assign(:download_progress, prune_progress(socket.assigns.download_progress, lists))}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("save", %{"blocklist" => params}, socket) do
    case Policy.create_blocklist(params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:blocklists, Policy.list_blocklists())
         |> assign(:form, to_form(Policy.change_blocklist(%Blocklist{})))
         |> put_flash(:info, create_flash(params))}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    list = Policy.get_blocklist!(id)

    case Policy.delete_blocklist(list) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:blocklists, Policy.list_blocklists())
         |> put_flash(:info, "Blocklist removed")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove blocklist")}
    end
  end

  def handle_event("refresh", %{"id" => id}, socket) do
    RefreshBlocklistWorker.enqueue(id, force: true)

    {:noreply,
     socket
     |> assign(:blocklists, Policy.list_blocklists())
     |> put_flash(:info, "Refresh queued")}
  end

  def handle_event("refresh_remote", _, socket) do
    count = ScheduleBlocklistRefreshWorker.enqueue_due(force: true)

    {:noreply,
     socket
     |> assign(:blocklists, Policy.list_blocklists())
     |> put_flash(:info, "Refresh queued for #{count} remote lists")}
  end

  def handle_event("create_category", %{"category" => params}, socket) do
    case Policy.create_category(params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:categories, Policy.list_categories())
         |> assign(:category_form, to_form(Policy.change_category(%Category{})))
         |> put_flash(:info, "Category created")}

      {:error, changeset} ->
        {:noreply, assign(socket, category_form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-3xl font-semibold">Blocklists</h1>
      <p class="mt-2 opacity-70">
        Remote lists are fetched when created, then every 5 minutes when due.
      </p>
      <button id="refresh-remote" class="btn btn-sm mt-4" type="button" phx-click="refresh_remote">
        Refresh remote lists
      </button>
      <ul class="mt-6 space-y-2">
        <li
          :for={list <- @blocklists}
          id={"blocklist-#{list.id}"}
          class="flex flex-wrap items-center gap-3"
        >
          <.link navigate={~p"/blocklists/#{list.id}"} class="link">{list.name}</.link>
          <span>({list.category && list.category.slug}) {list.source_type}/{list.format}</span>
          <span id={"blocklist-stats-#{list.id}"} class="opacity-70">
            {entry_count(list)} entries · last read {format_read_at(list)}
          </span>
          <.refresh_status list={list} progress={progress_for(@download_progress, list)} />
          <button
            :if={list.source_type == "remote"}
            id={"refresh-blocklist-#{list.id}"}
            class="btn btn-xs"
            type="button"
            phx-click="refresh"
            phx-value-id={list.id}
            disabled={Blocklist.downloading?(list)}
          >
            Refresh
          </button>
          <button
            id={"delete-blocklist-#{list.id}"}
            class="btn btn-xs"
            type="button"
            phx-click="delete"
            phx-value-id={list.id}
            data-confirm="Remove this blocklist?"
          >
            Remove
          </button>
        </li>
      </ul>

      <%= if @categories == [] do %>
        <div id="empty-categories" class="mt-8 max-w-md space-y-3">
          <p>
            Create a category before adding a blocklist, or go to <.link
              navigate={~p"/categories"}
              class="link"
            >Categories</.link>.
          </p>
          <.form
            for={@category_form}
            id="category-form"
            phx-submit="create_category"
            class="space-y-3"
          >
            <.input field={@category_form[:slug]} label="Slug" />
            <.input field={@category_form[:name]} label="Name" />
            <button class="btn btn-primary">Create category</button>
          </.form>
        </div>
      <% else %>
        <.form for={@form} id="blocklist-form" phx-submit="save" class="mt-8 space-y-3 max-w-md">
          <.input field={@form[:name]} label="Name" />
          <.input
            field={@form[:category_id]}
            type="select"
            label="Category"
            prompt="Select a category"
            options={Enum.map(@categories, &{&1.name, &1.id})}
          />
          <.input
            field={@form[:source_type]}
            type="select"
            label="Source"
            options={[{"manual", "manual"}, {"remote", "remote"}]}
          />
          <.input field={@form[:source_url]} label="Source URL" />
          <.input
            field={@form[:format]}
            type="select"
            label="Format"
            options={[{"domains", "domains"}, {"hosts", "hosts"}, {"urls", "urls"}]}
          />
          <button class="btn btn-primary">Create</button>
        </.form>
      <% end %>
    </Layouts.app>
    """
  end

  defp create_flash(%{"source_type" => "remote"}),
    do: "Blocklist created; fetching entries"

  defp create_flash(_), do: "Blocklist created"

  defp entry_count(%{active_version: %{entry_count: count}}) when is_integer(count), do: count
  defp entry_count(_), do: 0

  defp format_read_at(%{last_success_at: %DateTime{} = at}), do: format_time(at)
  defp format_read_at(%{last_attempt_at: %DateTime{} = at}), do: "#{format_time(at)} (failed)"
  defp format_read_at(_), do: "never"

  defp format_time(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")

  defp keep_active_progress(socket, id, progress) do
    id = to_string(id)

    if Enum.any?(socket.assigns.blocklists, &downloading_id?(&1, id)) do
      %{id => progress}
    else
      socket.assigns.download_progress
    end
  end

  defp prune_progress(progress, lists) do
    active_ids =
      MapSet.new(
        for list <- lists,
            list.refresh_status in ~w(downloading importing),
            do: to_string(list.id)
      )

    Map.filter(progress, fn {id, _} -> MapSet.member?(active_ids, to_string(id)) end)
  end

  defp progress_for(progress, list) do
    if list.refresh_status in ~w(downloading importing) do
      Map.get(progress, list.id) || Map.get(progress, to_string(list.id))
    end
  end

  defp downloading_id?(list, id),
    do: list.refresh_status in ~w(downloading importing) and to_string(list.id) == id
end
