defmodule TaskmasterWeb.EventForm do
  @moduledoc """
  The one modal that writes an event or a chore — new or existing.

  Markup only. Every field renders its value from the `form` map rather than
  from the database row or from whatever the browser happens to be holding,
  because a LiveView patch overwrites an input the server did not render
  (pattern P1 in the `bug-patterns` skill). The map is owned by
  `TaskmasterWeb.AppLive`, which also owns every handler the form names:

      phx-change="event_form_changed"
      phx-submit="save_event"
      phx-click="close_event_form" | "delete_event"

  It lives in `AppLive` rather than in `CalendarLive` because both the calendar
  and the chore list open it, and `CalendarLive` cannot render a modal for a
  screen it is not on.
  """

  use TaskmasterWeb, :html

  alias Taskmaster.Events.Event

  attr :form, :map, required: true, doc: "the field values, all strings"
  attr :editing, :boolean, required: true, doc: "false for a new row"
  attr :people, :list, required: true
  attr :audio, :boolean, required: true, doc: "false hides the alert checkbox"

  def event_form(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div class="bg-base-100 rounded-lg p-6 w-full max-w-lg shadow-xl max-h-[95vh] overflow-y-auto">
        <h2 class="text-3xl font-bold mb-4">
          {if @editing, do: "Edit Event / Task", else: "Add Event / Task"}
        </h2>
        <form id="event-form" phx-change="event_form_changed" phx-submit="save_event">
          <div class="mb-3">
            <label class="label text-xl">Title</label>
            <input
              type="text"
              name="title"
              value={@form["title"]}
              class="input input-lg input-bordered w-full text-xl"
              required
              autofocus
              phx-debounce="250"
            />
          </div>

          <%!-- Date and time share a row: the modal is nine controls tall on a
                board that is often in landscape. An empty time is an all-day
                row, and clearing it is how you get back to one. --%>
          <div class="mb-3 grid grid-cols-2 gap-3">
            <div>
              <label class="label text-xl">Date</label>
              <input
                type="date"
                name="start_date"
                value={@form["start_date"]}
                class="input input-lg input-bordered w-full text-xl"
                required
              />
            </div>
            <div>
              <label class="label text-xl">Time</label>
              <input
                type="time"
                name="start_time"
                value={@form["start_time"]}
                class="input input-lg input-bordered w-full text-xl"
              />
            </div>
          </div>

          <div class="mb-3">
            <label class="label text-xl">Type</label>
            <select name="type" class="select select-lg select-bordered w-full text-xl">
              <option value="event" selected={@form["type"] == "event"}>Event</option>
              <option value="task" selected={@form["type"] == "task"}>Task / Chore</option>
            </select>
          </div>

          <div class="mb-3">
            <label class="label text-xl">Assign To</label>
            <select name="person_id" class="select select-lg select-bordered w-full text-xl">
              <option value="" selected={@form["person_id"] == ""}>Nobody</option>
              <option
                :for={p <- @people}
                value={p.id}
                selected={@form["person_id"] == to_string(p.id)}
              >
                {p.name}
              </option>
            </select>
          </div>

          <div class="mb-3">
            <label class="label text-xl">Frequency</label>
            <select name="recurrence_type" class="select select-lg select-bordered w-full text-xl">
              <option
                :for={{value, label} <- frequencies()}
                value={value}
                selected={@form["recurrence_type"] == value}
              >
                {label}
              </option>
            </select>
          </div>

          <div :if={interval_unit(@form["recurrence_type"])} class="mb-3">
            <label class="label text-xl">{interval_unit(@form["recurrence_type"])}</label>
            <input
              type="number"
              name="recurrence_interval"
              value={@form["recurrence_interval"]}
              min="1"
              class="input input-lg input-bordered w-full text-xl"
            />
          </div>

          <%!-- Alert. The hidden input makes an unchecked box send "false"
                instead of sending nothing at all. The whole block goes with
                audio off, and `AppLive` then leaves the column alone rather
                than reading the missing key as false — editing a row on a
                silent board must not disarm it. --%>
          <div :if={@audio} class="mb-3 flex items-center gap-3">
            <label class="label cursor-pointer justify-start gap-3 text-xl flex-1">
              <input type="hidden" name="alert" value="false" />
              <input
                type="checkbox"
                name="alert"
                value="true"
                checked={@form["alert"] == "true"}
                class="checkbox checkbox-lg checkbox-primary"
              />
              <span>&#128276; Chime and read aloud</span>
            </label>
            <button
              type="button"
              phx-click={JS.dispatch("taskmaster:test-alert", to: "#app-root")}
              class="btn btn-lg btn-outline text-lg"
            >
              Test
            </button>
          </div>

          <div class="flex gap-3 mt-4">
            <button type="submit" class="btn btn-lg btn-primary flex-1 text-xl">
              {if @editing, do: "Save", else: "Add"}
            </button>
            <button
              :if={@editing}
              type="button"
              phx-click="delete_event"
              phx-value-id={@form["id"]}
              class="btn btn-lg btn-outline btn-error text-xl"
            >
              Delete
            </button>
            <button
              type="button"
              phx-click="close_event_form"
              class="btn btn-lg btn-ghost flex-1 text-xl"
            >
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  # This select is the second copy of `Event.recurrence_types/0` — the schema
  # validates against that list, so a rule added to one and not the other is
  # either unreachable or refused on every save (pattern P3 in the
  # `bug-patterns` skill). The mismatch is a compile error rather than
  # something to notice later.
  @frequencies [
    {"", "One time"},
    {"daily", "Daily"},
    {"weekly", "Weekly"},
    {"monthly", "Monthly"},
    {"yearly", "Yearly"},
    {"every_n_days", "Every N days"},
    {"every_n_weeks", "Every N weeks"},
    {"every_n_months", "Every N months"}
  ]

  offered = Enum.map(@frequencies, &elem(&1, 0)) -- [""]

  if Enum.sort(offered) != Enum.sort(Event.recurrence_types()) do
    raise """
    The Frequency select and Event.recurrence_types/0 have drifted apart.
      select: #{inspect(Enum.sort(offered))}
      schema: #{inspect(Enum.sort(Event.recurrence_types()))}
    """
  end

  defp frequencies, do: @frequencies

  # The unit an interval is counted in, or nil for the frequencies that need no
  # interval at all. Doubles as the "should the interval field be shown?" test.
  defp interval_unit("every_n_days"), do: "Days"
  defp interval_unit("every_n_weeks"), do: "Weeks"
  defp interval_unit("every_n_months"), do: "Months"
  defp interval_unit(_), do: nil
end
