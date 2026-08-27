defmodule TaskmasterWeb.GroceryLive do
  use TaskmasterWeb, :live_component

  @impl true
  def update(assigns, socket) do
    items = assigns.items

    {:ok,
     socket
     |> assign(:id, assigns.id)
     |> assign(:meat_dairy, Enum.filter(items, &(&1.category == "meat_dairy")))
     |> assign(:produce, Enum.filter(items, &(&1.category == "produce")))
     |> assign(:other, Enum.filter(items, &(&1.category == "other")))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-4xl font-bold">Groceries</h1>
        <button phx-click="clear_groceries" class="btn btn-lg btn-error btn-outline text-xl">
          Clear All
        </button>
      </div>

      <%!-- Add item form --%>
      <form phx-submit="add_grocery_item" class="flex gap-3 mb-6">
        <input
          type="text"
          name="name"
          placeholder="Add item..."
          class="input input-lg input-bordered flex-1 text-2xl"
          autocomplete="off"
        />
        <button type="submit" class="btn btn-lg btn-primary text-xl">Add</button>
      </form>

      <%!-- Three columns --%>
      <div class="grid grid-cols-3 gap-4">
        <%!-- Meat & Dairy (Red) --%>
        <div>
          <h2 class="text-2xl font-bold text-red-600 mb-3 border-b-2 border-red-600 pb-2">
            Meat & Dairy
          </h2>
          <ul class="space-y-2">
            <li :for={item <- @meat_dairy} class="flex items-center gap-2">
              <button
                phx-click="toggle_grocery"
                phx-value-id={item.id}
                class={"text-2xl text-red-600 cursor-pointer flex-1 text-left py-2 #{if item.checked, do: "line-through opacity-50"}"}
              >
                {item.name}
              </button>
              <button
                phx-click="delete_grocery"
                phx-value-id={item.id}
                class="btn btn-sm btn-ghost text-error cursor-pointer"
              >
                X
              </button>
            </li>
          </ul>
        </div>

        <%!-- Produce (Green) --%>
        <div>
          <h2 class="text-2xl font-bold text-green-600 mb-3 border-b-2 border-green-600 pb-2">
            Produce
          </h2>
          <ul class="space-y-2">
            <li :for={item <- @produce} class="flex items-center gap-2">
              <button
                phx-click="toggle_grocery"
                phx-value-id={item.id}
                class={"text-2xl text-green-600 cursor-pointer flex-1 text-left py-2 #{if item.checked, do: "line-through opacity-50"}"}
              >
                {item.name}
              </button>
              <button
                phx-click="delete_grocery"
                phx-value-id={item.id}
                class="btn btn-sm btn-ghost text-error cursor-pointer"
              >
                X
              </button>
            </li>
          </ul>
        </div>

        <%!-- Everything Else (Black) --%>
        <div>
          <h2 class="text-2xl font-bold text-base-content mb-3 border-b-2 border-base-content pb-2">
            Everything Else
          </h2>
          <ul class="space-y-2">
            <li :for={item <- @other} class="flex items-center gap-2">
              <button
                phx-click="toggle_grocery"
                phx-value-id={item.id}
                class={"text-2xl text-base-content cursor-pointer flex-1 text-left py-2 #{if item.checked, do: "line-through opacity-50"}"}
              >
                {item.name}
              </button>
              <button
                phx-click="delete_grocery"
                phx-value-id={item.id}
                class="btn btn-sm btn-ghost text-error cursor-pointer"
              >
                X
              </button>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end
end
