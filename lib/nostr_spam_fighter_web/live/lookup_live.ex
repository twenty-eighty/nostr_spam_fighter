defmodule NostrSpamFighterWeb.LookupLive do
  use NostrSpamFighterWeb, :live_view

  alias NostrSpamFighter.Moderation.TargetState
  alias NostrSpamFighter.Policy.Normalizer

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Lookup",
       form: to_form(%{"query" => ""}, as: :lookup),
       result: nil,
       error: nil,
       checking: false,
       lookup_id: 0
     )}
  end

  @impl true
  def handle_event("check", %{"lookup" => %{"query" => query}}, socket) do
    query = String.trim(query)
    socket = begin_check(socket, query)

    case classify(query) do
      {:error, reason} ->
        {:noreply, finish(socket, {:error, reason})}

      {:domain, domain} ->
        {:noreply, finish(socket, TargetState.lookup_domain(domain))}

      {:url, url} ->
        lookup_id = socket.assigns.lookup_id

        {:noreply,
         socket
         |> assign_url_preview(url)
         |> assign(:checking, true)
         |> start_async(:lookup, fn -> {lookup_id, TargetState.lookup_url(url)} end,
           timeout: 35_000
         )}
    end
  end

  @impl true
  def handle_async(:lookup, {:ok, {lookup_id, outcome}}, socket) do
    if socket.assigns.lookup_id == lookup_id do
      {:noreply, finish(socket, outcome)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:lookup, {:exit, reason}, socket) do
    if socket.assigns.checking and not cancelled?(reason) do
      {:noreply, finish(socket, {:error, :lookup_failed})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 class="text-3xl font-semibold tracking-tight">Lookup</h1>
          <p class="mt-2 max-w-2xl text-sm leading-6 opacity-70">
            Check whether a domain or URL matches current policy, and which lists would apply.
            URLs follow redirects the same way article scans do.
          </p>
        </div>
      </div>

      <.form
        for={@form}
        id="lookup-form"
        phx-submit="check"
        class="mt-8 rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm"
      >
        <div class="flex flex-col gap-4 sm:flex-row sm:items-end">
          <div class="min-w-0 flex-1">
            <.input
              field={@form[:query]}
              id="lookup-query"
              label="Domain or URL"
              placeholder="evil.com or https://example.com/article"
              autocomplete="off"
            />
          </div>
          <button
            id="lookup-submit"
            class="btn btn-primary shrink-0 transition hover:brightness-105 disabled:opacity-60"
            type="submit"
            disabled={@checking}
            phx-disable-with="Checking..."
          >
            Check
          </button>
        </div>
      </.form>

      <p :if={@checking} id="lookup-checking" class="mt-6 flex items-center gap-2 text-sm opacity-70">
        <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" /> Following redirects…
      </p>

      <p :if={@error} id="lookup-error" class="mt-6 text-sm text-error">{@error}</p>

      <section :if={@result} id="lookup-result" class="mt-8 space-y-6">
        <div class={[
          "rounded-2xl border p-6 shadow-sm",
          verdict_surface(@result)
        ]}>
          <p id="lookup-verdict" class="text-xs font-semibold uppercase tracking-[0.22em] opacity-80">
            {verdict_label(@result)}
          </p>
          <p class="mt-3 font-mono text-xl font-medium break-all">{display_target(@result)}</p>
          <p class="mt-2 text-sm leading-6 opacity-80">{verdict_copy(@result)}</p>
          <dl class="mt-5 grid gap-3 text-sm sm:grid-cols-2">
            <div>
              <dt class="opacity-60">Host</dt>
              <dd class="font-mono">{@result.domain}</dd>
            </div>
            <div>
              <dt class="opacity-60">Registrable domain</dt>
              <dd class="font-mono">{@result.registrable_domain}</dd>
            </div>
            <div :if={@result.url}>
              <dt class="opacity-60">Original URL</dt>
              <dd class="font-mono break-all">{@result.url}</dd>
            </div>
            <div :if={@result.final_url && @result.final_url != @result.url}>
              <dt class="opacity-60">Final URL</dt>
              <dd class="font-mono break-all">{@result.final_url}</dd>
            </div>
            <div :if={@result.redirect_count && @result.redirect_count > 0}>
              <dt class="opacity-60">Redirects</dt>
              <dd>{@result.redirect_count}</dd>
            </div>
            <div :if={@result.resolution_status}>
              <dt class="opacity-60">Fetch</dt>
              <dd>{String.replace(@result.resolution_status, "_", " ")}</dd>
            </div>
          </dl>
        </div>

        <div class="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
          <h2 class="text-sm font-semibold uppercase tracking-[0.18em] opacity-70">Matching lists</h2>
          <p :if={@result.lists == []} id="lookup-lists-empty" class="mt-4 text-sm opacity-70">
            No enabled blocklist matches this host.
          </p>
          <ul :if={@result.lists != []} id="lookup-lists" class="mt-4 divide-y divide-base-300">
            <li
              :for={list <- @result.lists}
              id={"lookup-list-#{list.id}"}
              class="flex flex-wrap items-center justify-between gap-3 py-3 first:pt-0 last:pb-0"
            >
              <div class="min-w-0">
                <.link navigate={~p"/blocklists/#{list.id}"} class="link font-medium">
                  {list.name}
                </.link>
                <p class="mt-0.5 text-sm opacity-70">
                  {list.category_name}
                  <span class="opacity-50">({list.category_slug})</span>
                </p>
              </div>
              <span class={[
                "badge badge-sm",
                list.blocks_serving && "badge-error",
                !list.blocks_serving && "badge-ghost"
              ]}>
                {if list.blocks_serving, do: "blocks serving", else: "does not block serving"}
              </span>
            </li>
          </ul>
        </div>

        <div
          :if={show_hosts?(@result)}
          id="lookup-hosts"
          class="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm"
        >
          <h2 class="text-sm font-semibold uppercase tracking-[0.18em] opacity-70">
            Hosts checked
          </h2>
          <ul class="mt-4 space-y-3">
            <li :for={host <- @result.hosts} id={"lookup-host-#{host.host}"} class="text-sm">
              <span class="font-mono">{host.host}</span>
              <span :if={host.registrable_domain} class="opacity-60">
                · {host.registrable_domain}
              </span>
              <span class="opacity-70">
                · {length(host.lists)} {if length(host.lists) == 1, do: "list", else: "lists"}
              </span>
            </li>
          </ul>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp begin_check(socket, query) do
    socket
    |> cancel_async(:lookup)
    |> assign(
      form: to_form(%{"query" => query}, as: :lookup),
      result: nil,
      error: nil,
      checking: false,
      lookup_id: socket.assigns.lookup_id + 1
    )
  end

  defp assign_url_preview(socket, url) do
    with {:ok, normalized} <- Normalizer.normalize_url(url),
         host when is_binary(host) <- Normalizer.hostname_from_url(normalized),
         {:ok, result} <- TargetState.lookup_domain(host) do
      assign(socket,
        result: Map.merge(result, %{kind: :url, url: normalized}),
        error: nil
      )
    else
      _ -> socket
    end
  end

  defp finish(socket, {:ok, result}) do
    assign(socket, checking: false, result: result, error: nil)
  end

  defp finish(socket, {:error, reason}) do
    assign(socket, checking: false, result: nil, error: error_message(reason))
  end

  defp classify(query) do
    cond do
      query == "" ->
        {:error, :empty}

      byte_size(query) > max_url_bytes() ->
        {:error, :url_too_long}

      url?(query) ->
        {:url, ensure_scheme(query)}

      true ->
        {:domain, query}
    end
  end

  defp max_url_bytes do
    Application.get_env(:nostr_spam_fighter, :max_url_bytes, 4_096)
  end

  defp url?(query) do
    String.contains?(query, "://") or String.contains?(query, "/")
  end

  defp ensure_scheme(query) do
    if String.contains?(query, "://"), do: query, else: "https://" <> query
  end

  defp cancelled?({:shutdown, :cancel}), do: true
  defp cancelled?(:cancel), do: true
  defp cancelled?(_), do: false

  defp error_message(:empty), do: "Enter a domain or URL."
  defp error_message(:invalid_domain), do: "That doesn't look like a valid domain."
  defp error_message(:invalid_url), do: "That doesn't look like a valid URL."
  defp error_message(:url_too_long), do: "That value is too long to look up."
  defp error_message(:lookup_failed), do: "Lookup failed. Try again."
  defp error_message(_), do: "Could not check that value."

  defp verdict_label(%{blacklisted: true}), do: "Blocked"
  defp verdict_label(%{status: "matched"}), do: "Listed"
  defp verdict_label(_), do: "Not listed"

  defp verdict_copy(%{blacklisted: true}),
    do: "Current policy would block serving this target."

  defp verdict_copy(%{status: "matched"}),
    do: "It matches at least one list, but those categories do not block serving."

  defp verdict_copy(_), do: "No enabled blocklist currently matches this host."

  defp verdict_surface(%{blacklisted: true}),
    do: "border-error/30 bg-error/10"

  defp verdict_surface(%{status: "matched"}),
    do: "border-warning/30 bg-warning/10"

  defp verdict_surface(_),
    do: "border-success/30 bg-success/10"

  defp display_target(%{url: url}) when is_binary(url) and url != "", do: url
  defp display_target(%{domain: domain}), do: domain

  defp show_hosts?(%{hosts: hosts} = result) when is_list(hosts) do
    result.kind == :url or length(hosts) > 1
  end

  defp show_hosts?(_), do: false
end
