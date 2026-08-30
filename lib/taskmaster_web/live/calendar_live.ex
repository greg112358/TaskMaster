defmodule TaskmasterWeb.CalendarLive do
  use TaskmasterWeb, :live_component

  alias Taskmaster.Events.Recurrence

  @impl true
  def mount(socket) do
    today = Date.utc_today()

    {:ok,
     socket
     |> assign(:today, today)
     |> assign(:current_date, today)
     |> assign(:view_mode, :month)
     |> assign(:show_add_form, false)
     |> assign(:add_form_date, nil)
     |> assign(:form, blank_form())}
  end

  # Every field is rendered from here rather than left to live in the DOM.
  # Without that, any re-render — changing Frequency shows or hides the interval
  # field — can patch over an input whose value the server never knew about, and
  # a half-typed title disappears.
  defp blank_form do
    %{
      "title" => "",
      "type" => "event",
      "person_id" => "",
      "recurrence_type" => "",
      "recurrence_interval" => "1",
      "alert" => "false"
    }
  end

  @impl true
  def update(%{action: :prev} = _assigns, socket) do
    new_date =
      case socket.assigns.view_mode do
        :month -> shift_months(socket.assigns.current_date, -1)
        :week -> Date.add(socket.assigns.current_date, -7)
      end

    {:ok, assign(socket, :current_date, new_date)}
  end

  def update(%{action: :next} = _assigns, socket) do
    new_date =
      case socket.assigns.view_mode do
        :month -> shift_months(socket.assigns.current_date, 1)
        :week -> Date.add(socket.assigns.current_date, 7)
      end

    {:ok, assign(socket, :current_date, new_date)}
  end

  def update(%{action: :toggle_view} = _assigns, socket) do
    new_mode = if socket.assigns.view_mode == :month, do: :week, else: :month
    {:ok, assign(socket, :view_mode, new_mode)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:events, assigns.events)
     |> assign(:people, assigns.people)
     |> assign(:audio, assigns.audio)
     |> assign(:id, assigns.id)}
  end

  defp shift_months(date, n) do
    total = date.year * 12 + (date.month - 1) + n
    year = div(total, 12)
    month = rem(total, 12) + 1
    day = min(date.day, Date.days_in_month(Date.new!(year, month, 1)))
    Date.new!(year, month, day)
  end

  defp month_grid(date) do
    first = Date.beginning_of_month(date)
    last = Date.end_of_month(date)

    # Monday = 1, Sunday = 7
    start_dow = Date.day_of_week(first)
    pad_before = start_dow - 1
    start_date = Date.add(first, -pad_before)

    end_dow = Date.day_of_week(last)
    pad_after = 7 - end_dow
    end_date = Date.add(last, pad_after)

    Date.range(start_date, end_date) |> Enum.to_list()
  end

  defp week_dates(date) do
    dow = Date.day_of_week(date)
    monday = Date.add(date, -(dow - 1))
    Enum.map(0..6, &Date.add(monday, &1))
  end

  defp events_for_date(events, date) do
    Enum.filter(events, fn event ->
      range_start = date
      range_end = date
      occurrences = Recurrence.occurrences_in_range(event, range_start, range_end)
      occurrences != []
    end)
  end

  defp month_name(date) do
    Calendar.strftime(date, "%B %Y")
  end

  defp week_label(date) do
    monday = Date.add(date, -(Date.day_of_week(date) - 1))
    sunday = Date.add(monday, 6)
    "#{Calendar.strftime(monday, "%b %d")} - #{Calendar.strftime(sunday, "%b %d, %Y")}"
  end

  defp day_name(date) do
    Calendar.strftime(date, "%a")
  end

  defp in_current_month?(date, current_date) do
    date.month == current_date.month && date.year == current_date.year
  end

  # The unit an interval is counted in, or nil for the frequencies that need no
  # interval at all. Doubles as the "should the interval field be shown?" test.
  defp interval_unit("every_n_days"), do: "Days"
  defp interval_unit("every_n_weeks"), do: "Weeks"
  defp interval_unit("every_n_months"), do: "Months"
  defp interval_unit(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Calendar header --%>
      <div class="flex items-center justify-between mb-4">
        <button phx-click="calendar_prev" class="btn btn-lg btn-ghost text-3xl">&larr;</button>
        <h1 class="text-4xl font-bold">
          {if @view_mode == :month, do: month_name(@current_date), else: week_label(@current_date)}
        </h1>
        <button phx-click="calendar_next" class="btn btn-lg btn-ghost text-3xl">&rarr;</button>
      </div>

      <div class="flex justify-center mb-4">
        <button phx-click="calendar_toggle_view" class="btn btn-lg btn-outline text-xl">
          {if @view_mode == :month, do: "Week View", else: "Month View"}
        </button>
      </div>

      <%!-- Day headers --%>
      <div class="grid grid-cols-7 gap-1 mb-1">
        <div
          :for={day <- ~w(Mon Tue Wed Thu Fri Sat Sun)}
          class="text-center text-lg font-bold text-base-content/60 py-1"
        >
          {day}
        </div>
      </div>

      <%!-- Month grid --%>
      <div :if={@view_mode == :month} class="grid grid-cols-7 gap-1">
        <div
          :for={date <- month_grid(@current_date)}
          class={"min-h-20 p-1 rounded border cursor-pointer
            #{if date == @today, do: "border-primary border-2", else: "border-base-300"}
            #{if in_current_month?(date, @current_date), do: "bg-base-100", else: "bg-base-200/50 text-base-content/40"}"}
          phx-click="add_event_for_date"
          phx-value-date={Date.to_iso8601(date)}
          phx-target={@myself}
        >
          <div class="text-lg font-semibold">{date.day}</div>
          <div
            :for={event <- events_for_date(@events, date)}
            class={"text-xs px-1 rounded mb-0.5 truncate
            #{if event.type == "task", do: "bg-warning/30 text-warning-content", else: "bg-info/30 text-info-content"}"}
          >
            <span :if={@audio and event.alert} title="Chimes and reads aloud">&#128276;</span>{event.title}
          </div>
        </div>
      </div>

      <%!-- Week view --%>
      <div :if={@view_mode == :week} class="grid grid-cols-7 gap-2">
        <div
          :for={date <- week_dates(@current_date)}
          class={"min-h-64 p-2 rounded border
            #{if date == @today, do: "border-primary border-2", else: "border-base-300"}"}
          phx-click="add_event_for_date"
          phx-value-date={Date.to_iso8601(date)}
          phx-target={@myself}
        >
          <div class="text-xl font-bold mb-2">{day_name(date)} {date.day}</div>
          <div
            :for={event <- events_for_date(@events, date)}
            class={"text-base p-2 rounded mb-1
            #{if event.type == "task", do: "bg-warning/30", else: "bg-info/30"}"}
          >
            <div class="font-semibold">
              <span :if={@audio and event.alert} title="Chimes and reads aloud">&#128276;</span>{event.title}
            </div>
            <div :if={event.person} class="text-sm text-base-content/60">{event.person.name}</div>
          </div>
        </div>
      </div>

      <%!-- Add event modal --%>
      <div
        :if={@show_add_form}
        class="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
      >
        <div class="bg-base-100 rounded-lg p-6 w-full max-w-lg shadow-xl">
          <h2 class="text-3xl font-bold mb-4">Add Event / Task</h2>
          <form
            id="add-event-form"
            phx-change="form_changed"
            phx-submit="add_event"
            phx-target={@myself}
          >
            <input type="hidden" name="start_date" value={@add_form_date} />

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
                  :for={
                    {value, label} <- [
                      {"", "One time"},
                      {"daily", "Daily"},
                      {"weekly", "Weekly"},
                      {"monthly", "Monthly"},
                      {"yearly", "Yearly"},
                      {"every_n_days", "Every N days"},
                      {"every_n_weeks", "Every N weeks"},
                      {"every_n_months", "Every N months"}
                    ]
                  }
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
                  instead of sending nothing at all. The whole block goes
                  with audio off, so the form sends no `alert` key and every
                  new event saves with alert=false. --%>
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
              <button type="submit" class="btn btn-lg btn-primary flex-1 text-xl">Add</button>
              <button
                type="button"
                phx-click="close_form"
                phx-target={@myself}
                class="btn btn-lg btn-ghost flex-1 text-xl"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("add_event_for_date", %{"date" => date}, socket) do
    {:noreply,
     socket
     |> assign(:show_add_form, true)
     |> assign(:add_form_date, date)
     |> assign(:form, blank_form())}
  end

  # Form-level, so a change to any one field carries the rest with it and the
  # server always holds what is on screen.
  def handle_event("form_changed", params, socket) do
    {:noreply, assign(socket, :form, Map.merge(socket.assigns.form, form_fields(params)))}
  end

  def handle_event("close_form", _params, socket) do
    {:noreply, assign(socket, :show_add_form, false)}
  end

  def handle_event("add_event", params, socket) do
    send(self(), {:add_event_from_form, params})

    {:noreply, assign(socket, :show_add_form, false)}
  end

  # Ignore anything not part of the form, and drop absent keys so a hidden
  # interval field does not wipe the value it had.
  defp form_fields(params) do
    params
    |> Map.take(Map.keys(blank_form()))
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end
end
