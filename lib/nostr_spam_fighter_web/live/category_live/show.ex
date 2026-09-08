defmodule NostrSpamFighterWeb.CategoryLive.Show do
  use NostrSpamFighterWeb, :live_view
  alias NostrSpamFighter.Policy

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    category = Policy.get_category!(id)

    {:ok,
     assign(socket,
       page_title: category.name,
       category: category,
       form: to_form(Policy.change_category(category))
     )}
  end

  @impl true
  def handle_event("save", %{"category" => params}, socket) do
    case Policy.update_category(socket.assigns.category, params) do
      {:ok, category} ->
        {:noreply,
         assign(socket, category: category, form: to_form(Policy.change_category(category)))}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-3xl font-semibold">{@category.name}</h1>
      <.form for={@form} phx-submit="save" class="mt-6 space-y-3 max-w-md">
        <.input field={@form[:name]} label="Name" />
        <.input field={@form[:description]} label="Description" type="textarea" />
        <.input field={@form[:enabled]} label="Enabled" type="checkbox" />
        <.input field={@form[:blocks_serving]} label="Blocks serving" type="checkbox" />
        <button class="btn btn-primary">Save</button>
      </.form>
    </Layouts.app>
    """
  end
end
