defmodule NostrSpamFighterWeb.ApiKeyLive.Index do
  use NostrSpamFighterWeb, :live_view
  alias NostrSpamFighter.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "API keys",
       keys: Accounts.list_api_keys(),
       created: nil,
       confirm_revoke: nil,
       form: to_form(%{"name" => "", "scopes" => ["articles:moderation:read"]})
     )}
  end

  @impl true
  def handle_event("create", params, socket) do
    attrs = params["api_key"] || params

    case Accounts.create_api_key(attrs, socket.assigns.current_admin) do
      {:ok, key} ->
        {:noreply, assign(socket, keys: Accounts.list_api_keys(), created: key.plaintext)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create key")}
    end
  end

  def handle_event("disable", %{"id" => id}, socket) do
    {:ok, _} = Accounts.disable_api_key(Accounts.get_api_key!(id))
    {:noreply, assign(socket, keys: Accounts.list_api_keys())}
  end

  def handle_event("enable", %{"id" => id}, socket) do
    case Accounts.enable_api_key(Accounts.get_api_key!(id)) do
      {:ok, _} -> {:noreply, assign(socket, keys: Accounts.list_api_keys())}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Cannot enable revoked key")}
    end
  end

  def handle_event("confirm_revoke", %{"id" => id}, socket) do
    {:noreply, assign(socket, confirm_revoke: id)}
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    {:ok, _} = Accounts.revoke_api_key(Accounts.get_api_key!(id))
    {:noreply, assign(socket, keys: Accounts.list_api_keys(), confirm_revoke: nil)}
  end

  def handle_event("rotate", %{"id" => id}, socket) do
    {:ok, key} = Accounts.rotate_api_key(Accounts.get_api_key!(id), socket.assigns.current_admin)
    {:noreply, assign(socket, keys: Accounts.list_api_keys(), created: key.plaintext)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-3xl font-semibold">API keys</h1>
      <p :if={@created} class="mt-4 font-mono break-all">Copy now: {@created}</p>
      <ul class="mt-6 space-y-3">
        <li :for={key <- @keys}>
          <strong>{key.name}</strong>
          nsf_{key.key_prefix}_… {Enum.join(key.scopes, ", ")}
          {if key.enabled, do: "enabled", else: "disabled"}
          {if key.revoked_at, do: "revoked"} expires {key.expires_at} last used {key.last_used_at}
          <button class="btn btn-xs" phx-click="disable" phx-value-id={key.id}>disable</button>
          <button class="btn btn-xs" phx-click="enable" phx-value-id={key.id}>enable</button>
          <button class="btn btn-xs" phx-click="rotate" phx-value-id={key.id}>rotate</button>
          <button class="btn btn-xs" phx-click="confirm_revoke" phx-value-id={key.id}>revoke</button>
          <button
            :if={@confirm_revoke == key.id}
            class="btn btn-xs btn-error"
            phx-click="revoke"
            phx-value-id={key.id}
          >
            confirm revoke
          </button>
        </li>
      </ul>
      <form phx-submit="create" class="mt-8 space-y-3 max-w-md">
        <input type="text" name="name" class="input" placeholder="Name" />
        <label class="flex gap-2 items-center">
          <input type="checkbox" name="scopes[]" value="articles:moderation:read" checked />
          articles:moderation:read
        </label>
        <input type="datetime-local" name="expires_at" class="input" />
        <button class="btn btn-primary">Create key</button>
      </form>
    </Layouts.app>
    """
  end
end
