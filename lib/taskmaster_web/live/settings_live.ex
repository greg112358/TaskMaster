defmodule TaskmasterWeb.SettingsLive do
  use TaskmasterWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:id, assigns.id)
     |> assign(:people, assigns.people)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-4xl font-bold mb-6">Family Members</h1>

      <form phx-submit="add_person" class="flex gap-3 mb-6">
        <input
          type="text"
          name="name"
          placeholder="Add person..."
          class="input input-lg input-bordered flex-1 text-2xl"
          autocomplete="off"
        />
        <button type="submit" class="btn btn-lg btn-primary text-xl">Add</button>
      </form>

      <div :if={@people == []} class="text-2xl text-base-content/50 text-center py-12">
        No family members added yet.
      </div>

      <ul class="space-y-3">
        <li
          :for={person <- @people}
          class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
        >
          <span class="text-3xl font-semibold">{person.name}</span>
          <button
            phx-click="delete_person"
            phx-value-id={person.id}
            class="btn btn-lg btn-error btn-outline text-xl"
          >
            Remove
          </button>
        </li>
      </ul>
    </div>
    """
  end
end
