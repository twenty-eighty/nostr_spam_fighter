defmodule NostrSpamFighterWeb.AdminLive.Index do
  use NostrSpamFighterWeb, :live_view
  alias NostrSpamFighter.Accounts
  alias NostrSpamFighter.Accounts.Admin

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Admins",
       admins: Accounts.list_admins(),
       form: to_form(Accounts.change_admin(%Admin{}))
     )}
  end

  @impl true
  def handle_event("save", %{"admin" => params}, socket) do
    case Accounts.create_admin(params) do
      {:ok, _} -> {:noreply, assign(socket, admins: Accounts.list_admins())}
      {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    admin = Accounts.get_admin!(id)
    {:ok, _} = Accounts.update_admin(admin, %{enabled: !admin.enabled})
    {:noreply, assign(socket, admins: Accounts.list_admins())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-3xl font-semibold">Admins</h1>
      <ul class="mt-6 space-y-2">
        <li :for={admin <- @admins}>
          {admin.pubkey} {admin.name} {if admin.enabled, do: "enabled", else: "disabled"}
          <button class="btn btn-xs" phx-click="toggle" phx-value-id={admin.id}>toggle</button>
        </li>
      </ul>
      <.form for={@form} phx-submit="save" class="mt-8 space-y-3 max-w-md">
        <.input field={@form[:pubkey]} label="Pubkey" />
        <.input field={@form[:name]} label="Name" />
        <button class="btn btn-primary">Add</button>
      </.form>
    </Layouts.app>
    """
  end
end
