defmodule TaskmasterWeb.GroceryLive do
  @moduledoc """
  The Groceries screen.

  Like `TaskmasterWeb.CalendarLive` — and unlike the other components — this one
  keeps local state, because the typed query, the suggestion list and the two
  dialogs are view state nobody outside this screen needs. Writes still go
  through `AppLive`: local UI events carry `phx-target={@myself}`, and anything
  that touches the database is handed up with `send(self(), ...)`.
  """

  use TaskmasterWeb, :live_component

  alias Taskmaster.Grocery.Dictionary

  # Shown next to each category in the two dialogs, in list order.
  @category_labels [
    {"meat_dairy", "Meat & Dairy", "text-red-600", "border-red-600"},
    {"produce", "Produce", "text-green-600", "border-green-600"},
    {"other", "Everything Else", "text-base-content", "border-base-content"}
  ]

  @impl true
  def mount(socket) do
    {:ok, reset_form(socket)}
  end

  # Sent up from AppLive when the long-press hook fires on an item.
  @impl true
  def update(%{confirm_forget: name}, socket) do
    {:ok, assign(socket, :forgetting, resolve_forget(name))}
  end

  # A dictionary edit has landed; whatever is on screen is now stale.
  def update(%{refresh_suggestions: true}, socket) do
    {:ok, assign(socket, :suggestions, Dictionary.suggest(socket.assigns.query))}
  end

  def update(assigns, socket) do
    items = assigns.items

    {:ok,
     socket
     |> assign(:id, assigns.id)
     |> assign(:meat_dairy, Enum.filter(items, &(&1.category == "meat_dairy")))
     |> assign(:produce, Enum.filter(items, &(&1.category == "produce")))
     |> assign(:other, Enum.filter(items, &(&1.category == "other")))}
  end

  defp reset_form(socket) do
    socket
    |> assign(:query, "")
    |> assign(:suggestions, [])
    # The name waiting for somebody to say which list it belongs on.
    |> assign(:categorizing, nil)
    # The name waiting for somebody to confirm forgetting it.
    |> assign(:forgetting, nil)
  end

  # Holding "whole milk" should offer to forget "milk" — the entry actually
  # responsible for its colour — rather than a word the dictionary never held.
  defp resolve_forget(name) do
    case Dictionary.matching_term(name) do
      nil -> {:unknown, name}
      term -> {:term, term.name}
    end
  end

  defp category_text_class(category) do
    Enum.find_value(@category_labels, "", fn {value, _, text, _} -> value == category && text end)
  end

  @impl true
  def handle_event("suggest", %{"name" => name}, socket) do
    {:noreply,
     socket
     |> assign(:query, name)
     |> assign(:suggestions, Dictionary.suggest(name))}
  end

  # Adding is two different jobs depending on whether the board knows the word.
  def handle_event("submit_item", %{"name" => name}, socket) do
    case Dictionary.category_for(name) do
      {:ok, category} ->
        send(self(), {:add_grocery_item, name, category})
        {:noreply, reset_form(socket)}

      :unknown ->
        case String.trim(name) do
          "" -> {:noreply, socket}
          trimmed -> {:noreply, assign(socket, :categorizing, trimmed)}
        end
    end
  end

  def handle_event("use_suggestion", %{"name" => name, "category" => category}, socket) do
    send(self(), {:add_grocery_item, name, category})
    {:noreply, reset_form(socket)}
  end

  # Answering the "which list?" dialog both files the item and teaches the word,
  # so the question is only ever asked once.
  def handle_event("categorize", %{"category" => category}, socket) do
    send(self(), {:learn_grocery_term, socket.assigns.categorizing, category})
    {:noreply, reset_form(socket)}
  end

  def handle_event("cancel_categorize", _params, socket) do
    {:noreply, assign(socket, :categorizing, nil)}
  end

  def handle_event("ask_forget", %{"name" => name}, socket) do
    {:noreply, assign(socket, :forgetting, resolve_forget(name))}
  end

  def handle_event("forget", _params, socket) do
    {:term, name} = socket.assigns.forgetting
    send(self(), {:forget_grocery_term, name})

    # The suggestion list is refreshed by the :dictionary_changed broadcast once
    # the delete has actually happened — recomputing it here would run before
    # the write and leave the forgotten word on screen.
    {:noreply, assign(socket, :forgetting, nil)}
  end

  def handle_event("cancel_forget", _params, socket) do
    {:noreply, assign(socket, :forgetting, nil)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :category_labels, @category_labels)

    ~H"""
    <div>
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-4xl font-bold">Groceries</h1>
        <button phx-click="clear_groceries" class="btn btn-lg btn-error btn-outline text-xl">
          Clear All
        </button>
      </div>

      <%!-- Add item, with suggestions from the dictionary as you type --%>
      <div class="relative mb-6">
        <form
          id="grocery-form"
          phx-change="suggest"
          phx-submit="submit_item"
          phx-target={@myself}
          class="flex gap-3"
        >
          <input
            type="text"
            name="name"
            value={@query}
            placeholder="Add item..."
            class="input input-lg input-bordered flex-1 text-2xl"
            autocomplete="off"
            phx-debounce="120"
          />
          <button type="submit" class="btn btn-lg btn-primary text-xl">Add</button>
        </form>

        <ul
          :if={@suggestions != []}
          id="grocery-suggestions"
          class="absolute z-40 left-0 right-0 mt-1 bg-base-100 border-2 border-base-300 rounded-lg shadow-xl overflow-hidden"
        >
          <li
            :for={term <- @suggestions}
            class="flex items-center border-b border-base-200 last:border-b-0"
          >
            <button
              type="button"
              phx-click="use_suggestion"
              phx-value-name={term.name}
              phx-value-category={term.category}
              phx-target={@myself}
              class={"flex-1 text-left text-2xl px-4 py-4 hover:bg-base-200 cursor-pointer #{category_text_class(term.category)}"}
            >
              {term.name}
            </button>
            <button
              type="button"
              phx-click="ask_forget"
              phx-value-name={term.name}
              phx-target={@myself}
              title={"Delete #{term.name}"}
              aria-label={"Delete #{term.name}"}
              class="px-5 py-4 text-3xl font-bold text-red-600 hover:bg-red-600/10 cursor-pointer"
            >
              &times;
            </button>
          </li>
        </ul>
      </div>

      <%!-- Three columns --%>
      <div class="grid grid-cols-3 gap-4">
        <div :for={{category, label, text_class, border_class} <- @category_labels}>
          <h2 class={"text-2xl font-bold mb-3 border-b-2 pb-2 #{text_class} #{border_class}"}>
            {label}
          </h2>
          <ul class="space-y-2">
            <li
              :for={item <- items_for(assigns, category)}
              id={"grocery-item-#{item.id}"}
              phx-hook="LongPress"
              data-name={item.name}
              class="flex items-center gap-2 rounded select-none"
            >
              <button
                phx-click="toggle_grocery"
                phx-value-id={item.id}
                class={"text-2xl cursor-pointer flex-1 text-left py-2 #{text_class} #{if item.checked, do: "line-through opacity-50"}"}
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

      <p class="mt-6 text-base text-base-content/50">Hold to delete word.</p>

      <%!-- "Which list?" — shown when the board does not know the word --%>
      <div
        :if={@categorizing}
        id="categorize-dialog"
        class="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
      >
        <div class="bg-base-100 rounded-lg p-6 w-full max-w-lg shadow-xl">
          <h2 class="text-3xl font-bold mb-5">{@categorizing}</h2>

          <div class="flex flex-col gap-3">
            <button
              :for={{category, label, text_class, border_class} <- @category_labels}
              phx-click="categorize"
              phx-value-category={category}
              phx-target={@myself}
              class={"btn btn-lg btn-outline text-2xl justify-start #{text_class} #{border_class}"}
            >
              {label}
            </button>
          </div>

          <button
            phx-click="cancel_categorize"
            phx-target={@myself}
            class="btn btn-lg btn-ghost w-full text-xl mt-4"
          >
            Cancel
          </button>
        </div>
      </div>

      <%!-- "Are you sure?" — shown before anything is forgotten --%>
      <div
        :if={@forgetting}
        id="forget-dialog"
        class="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
      >
        <div
          :if={match?({:term, _}, @forgetting)}
          class="bg-base-100 rounded-lg p-6 w-full max-w-lg shadow-xl"
        >
          <h2 class="text-3xl font-bold mb-5">Delete "{elem(@forgetting, 1)}"?</h2>

          <div class="flex gap-3">
            <button
              phx-click="forget"
              phx-target={@myself}
              class="btn btn-lg btn-error flex-1 text-xl"
            >
              Yes
            </button>
            <button
              phx-click="cancel_forget"
              phx-target={@myself}
              class="btn btn-lg btn-ghost flex-1 text-xl"
            >
              No
            </button>
          </div>
        </div>

        <%!-- Held an item whose word was never in the dictionary (added by
              voice, say). Nothing to delete, so say so rather than pretending. --%>
        <div
          :if={match?({:unknown, _}, @forgetting)}
          class="bg-base-100 rounded-lg p-6 w-full max-w-lg shadow-xl"
        >
          <h2 class="text-3xl font-bold mb-5">"{elem(@forgetting, 1)}" not in dictionary</h2>

          <button
            phx-click="cancel_forget"
            phx-target={@myself}
            class="btn btn-lg btn-ghost w-full text-xl"
          >
            OK
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp items_for(assigns, "meat_dairy"), do: assigns.meat_dairy
  defp items_for(assigns, "produce"), do: assigns.produce
  defp items_for(assigns, "other"), do: assigns.other
end
