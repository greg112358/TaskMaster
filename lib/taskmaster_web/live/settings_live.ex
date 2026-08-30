defmodule TaskmasterWeb.SettingsLive do
  @moduledoc """
  Family members.

  Presentational, like `ChoreListLive`: no `handle_event` of its own, so every
  click and change bubbles to `AppLive`, which also holds the half-typed name.
  It has to — an input LiveView renders without a `value` exists only in the DOM,
  and the next patch wipes it (see the `bug-patterns` skill, P1).
  """

  use TaskmasterWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:id, assigns.id)
     |> assign(:people, assigns.people)
     |> assign(:new_person_name, assigns.new_person_name)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-4xl font-bold mb-6">Family Members</h1>

      <form
        id="add-person-form"
        phx-change="person_form_changed"
        phx-submit="add_person"
        class="flex gap-3 mb-6"
      >
        <input
          type="text"
          name="name"
          value={@new_person_name}
          placeholder="Add person..."
          class="input input-lg input-bordered flex-1 text-2xl"
          autocomplete="off"
          phx-debounce="250"
        />
        <button type="submit" class="btn btn-lg btn-primary text-xl">Add</button>
      </form>

      <div :if={@people == []} class="text-2xl text-base-content/50 text-center py-12">
        None
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
