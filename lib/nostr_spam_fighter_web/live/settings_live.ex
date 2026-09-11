defmodule NostrSpamFighterWeb.SettingsLive do
  use NostrSpamFighterWeb, :live_view

  alias NostrSpamFighter.Policy.Namespace
  alias NostrSpamFighter.Scanner.{SkipHosts, SkipRedirectHost}

  @impl true
  def mount(_params, _session, socket) do
    SkipHosts.ensure_defaults()

    {:ok,
     assign(socket,
       page_title: "Settings",
       namespace: Namespace.content(),
       scanner: Application.get_env(:nostr_spam_fighter, :scanner_version),
       generation: NostrSpamFighter.Policy.Cache.generation(),
       skip_hosts: SkipHosts.list(),
       form: skip_form()
     )}
  end

  @impl true
  def handle_event("add_skip_host", %{"skip_host" => params}, socket) do
    case SkipHosts.create(params) do
      {:ok, row} ->
        {:noreply,
         socket
         |> assign(:skip_hosts, SkipHosts.list())
         |> assign(:form, skip_form())
         |> put_flash(:info, "Skip fetch for #{row.host}")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :skip_host))}
    end
  end

  def handle_event("delete_skip_host", %{"id" => id}, socket) do
    row = SkipHosts.get!(id)

    case SkipHosts.delete(row) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:skip_hosts, SkipHosts.list())
         |> put_flash(:info, "Removed #{row.host}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove host")}
    end
  end

  def handle_event("restore_skip_hosts", _params, socket) do
    SkipHosts.ensure_defaults()

    {:noreply,
     socket
     |> assign(:skip_hosts, SkipHosts.list())
     |> put_flash(:info, "Recommended media hosts are on the list")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div>
        <h1 class="text-3xl font-semibold tracking-tight">Settings</h1>
        <p class="mt-2 max-w-2xl text-sm leading-6 opacity-70">
          Scanner identity and hosts we match without opening an HTTP connection.
        </p>
      </div>

      <section class="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
        <h2 class="text-sm font-semibold uppercase tracking-[0.18em] opacity-60">Scanner</h2>
        <dl class="mt-4 grid gap-3 text-sm sm:grid-cols-3">
          <div>
            <dt class="opacity-60">NIP-32 namespace</dt>
            <dd class="mt-1 font-mono">{@namespace}</dd>
          </div>
          <div>
            <dt class="opacity-60">Scanner version</dt>
            <dd class="mt-1 font-mono">{@scanner}</dd>
          </div>
          <div>
            <dt class="opacity-60">Policy generation</dt>
            <dd class="mt-1 font-mono">{@generation}</dd>
          </div>
        </dl>
      </section>

      <section class="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div class="max-w-2xl">
            <h2 class="text-xl font-semibold tracking-tight">Skip redirect fetch</h2>
            <p class="mt-2 text-sm leading-6 opacity-70">
              These hostnames are matched against policy without a HEAD request.
              Use this for content-addressed media CDNs such as Blossom, where every
              object is a new path and following redirects would not change the host.
            </p>
          </div>
          <button
            id="restore-skip-hosts"
            type="button"
            class="btn btn-sm transition hover:brightness-105"
            phx-click="restore_skip_hosts"
          >
            Add recommended hosts
          </button>
        </div>

        <ul id="skip-hosts" class="mt-6 divide-y divide-base-300">
          <li :if={@skip_hosts == []} id="skip-hosts-empty" class="py-6 text-sm opacity-70">
            No hosts skipped — every URL is fetched with HEAD.
          </li>
          <li
            :for={row <- @skip_hosts}
            id={"skip-host-#{row.id}"}
            class="flex items-center justify-between gap-4 py-3"
          >
            <code class="text-sm">{row.host}</code>
            <button
              id={"skip-host-delete-#{row.id}"}
              type="button"
              class="btn btn-xs transition hover:brightness-105"
              phx-click="delete_skip_host"
              phx-value-id={row.id}
            >
              Remove
            </button>
          </li>
        </ul>

        <.form
          for={@form}
          id="skip-host-form"
          phx-submit="add_skip_host"
          class="mt-6 flex flex-col gap-4 sm:flex-row sm:items-end"
        >
          <div class="min-w-0 flex-1">
            <.input
              field={@form[:host]}
              id="skip-host-host"
              label="Hostname"
              placeholder="blossom.primal.net"
              autocomplete="off"
            />
          </div>
          <button
            id="skip-host-submit"
            type="submit"
            class="btn btn-primary shrink-0 transition hover:brightness-105"
          >
            Add host
          </button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  defp skip_form do
    %SkipRedirectHost{}
    |> SkipHosts.change()
    |> to_form(as: :skip_host)
  end
end
