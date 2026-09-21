defmodule TaskmasterWeb.CalendarLive do
  @moduledoc """
  The month/week grid.

  It holds the two pieces of state nobody outside this screen needs — which
  view, and which month or week is showing — and nothing else. Both arrive as
  `send_update` actions from `TaskmasterWeb.AppLive`, which handles the header
  buttons.

  Taps that write go straight to `AppLive` (no `phx-target`), so this component
  has no `handle_event` at all:

    * empty space in a day → `open_event_form`, carrying that day's date
    * an event inside a day → `edit_event`, carrying its id

  The two nest, which is what makes them one tap each: LiveView dispatches a
  click to the *closest* element carrying a binding (`closestPhxBinding` in
  `phoenix_live_view.esm.js`), so a tap on an event does not also open the
  add form behind it.
  """

  use TaskmasterWeb, :live_component

  alias Taskmaster.Clock
  alias Taskmaster.Events.Recurrence

  @impl true
  def mount(socket) do
    today = Clock.today()

    {:ok,
     socket
     |> assign(:today, today)
     |> assign(:current_date, today)
     |> assign(:view_mode, :month)}
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

  # A day reads in clock order, all-day rows first. The list arrives sorted by
  # `start_date`, which says nothing about where a recurring event falls on
  # *this* day, so the time sort happens here. `nil` is an atom and atoms
  # precede tuples in term order, so untimed rows come first for free.
  defp events_for_date(events, date) do
    events
    |> Enum.filter(fn event -> Recurrence.occurrences_in_range(event, date, date) != [] end)
    |> Enum.sort_by(&(&1.start_time && Time.to_erl(&1.start_time)))
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
          phx-click="open_event_form"
          phx-value-date={Date.to_iso8601(date)}
        >
          <div class="text-lg font-semibold">{date.day}</div>
          <div
            :for={event <- events_for_date(@events, date)}
            phx-click="edit_event"
            phx-value-id={event.id}
            class={"text-xs px-1 rounded mb-0.5 truncate
            #{if event.type == "task", do: "bg-warning/30 text-warning-content", else: "bg-info/30 text-info-content"}"}
          >
            <span :if={@audio and event.alert} title="Chimes and reads aloud">&#128276;</span><span
              :if={event.start_time}
              class="font-semibold mr-1"
            >{Clock.format_time_short(event.start_time)}</span>{event.title}
          </div>
        </div>
      </div>

      <%!-- Week view --%>
      <div :if={@view_mode == :week} class="grid grid-cols-7 gap-2">
        <div
          :for={date <- week_dates(@current_date)}
          class={"min-h-64 p-2 rounded border cursor-pointer
            #{if date == @today, do: "border-primary border-2", else: "border-base-300"}"}
          phx-click="open_event_form"
          phx-value-date={Date.to_iso8601(date)}
        >
          <div class="text-xl font-bold mb-2">{day_name(date)} {date.day}</div>
          <div
            :for={event <- events_for_date(@events, date)}
            phx-click="edit_event"
            phx-value-id={event.id}
            class={"text-base p-2 rounded mb-1
            #{if event.type == "task", do: "bg-warning/30", else: "bg-info/30"}"}
          >
            <div class="font-semibold">
              <span :if={@audio and event.alert} title="Chimes and reads aloud">&#128276;</span>{event.title}
            </div>
            <div :if={event.start_time} class="text-sm font-semibold">
              {Clock.format_time(event.start_time)}
            </div>
            <div :if={event.person} class="text-sm text-base-content/60">{event.person.name}</div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
