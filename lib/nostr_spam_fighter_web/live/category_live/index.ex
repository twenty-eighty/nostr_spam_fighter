defmodule NostrSpamFighterWeb.CategoryLive.Index do
  use NostrSpamFighterWeb, :live_view
  alias NostrSpamFighter.Policy
  alias NostrSpamFighter.Policy.Category

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Categories")
     |> assign(:categories, Policy.list_categories())
     |> assign(:form, to_form(Policy.change_category(%Category{})))}
  end

  @impl true
  def handle_event("save", %{"category" => params}, socket) do
    case Policy.create_category(params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:categories, Policy.list_categories())
         |> assign(:form, to_form(Policy.change_category(%Category{})))
         |> put_flash(:info, "Category created")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-3xl font-semibold">Categories</h1>
      <ul class="mt-6 space-y-2">
        <li :for={cat <- @categories}>
          <.link navigate={~p"/categories/#{cat.id}"} class="link">{cat.slug}</.link>
          — {cat.name} {if cat.enabled, do: "enabled", else: "disabled"}
          {if cat.blocks_serving, do: "blocks serving"}
        </li>
      </ul>
      <.form for={@form} id="category-form" phx-submit="save" class="mt-8 space-y-3 max-w-md">
        <.input field={@form[:slug]} label="Slug" />
        <.input field={@form[:name]} label="Name" />
        <.input field={@form[:description]} label="Description" type="textarea" />
        <.input field={@form[:enabled]} label="Enabled" type="checkbox" />
        <.input field={@form[:blocks_serving]} label="Blocks serving" type="checkbox" />
        <button class="btn btn-primary">Create</button>
      </.form>
    </Layouts.app>
    """
  end
end
