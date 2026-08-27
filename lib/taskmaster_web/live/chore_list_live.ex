defmodule TaskmasterWeb.ChoreListLive do
  use TaskmasterWeb, :live_component

  alias Taskmaster.Events

  @impl true
  def update(assigns, socket) do
    tasks_with_next =
      assigns.tasks
      |> Enum.map(fn task ->
        next = Events.next_occurrence(task)
        Map.put(task, :next_date, next)
      end)
      |> Enum.sort_by(fn t -> t.next_date || ~D[9999-12-31] end, Date)

    {:ok,
     socket
     |> assign(:id, assigns.id)
     |> assign(:tasks, tasks_with_next)}
  end

  defp format_date(nil), do: "-"
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")

  defp format_datetime(nil), do: "Never"

  defp format_datetime(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %Y %I:%M %p")
  end

  defp recurrence_label(nil, _), do: "One time"
  defp recurrence_label("daily", _), do: "Daily"
  defp recurrence_label("weekly", _), do: "Weekly"
  defp recurrence_label("monthly", _), do: "Monthly"
  defp recurrence_label("yearly", _), do: "Yearly"
  defp recurrence_label("every_n_days", n), do: "Every #{n} days"
  defp recurrence_label("every_n_weeks", n), do: "Every #{n} weeks"
  defp recurrence_label("every_n_months", n), do: "Every #{n} months"

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-4xl font-bold mb-6">Chores</h1>

      <div :if={@tasks == []} class="text-2xl text-base-content/50 text-center py-12">
        No chores scheduled. Add tasks via voice or calendar.
      </div>

      <div class="overflow-x-auto">
        <table :if={@tasks != []} class="table table-lg w-full">
          <thead>
            <tr class="text-xl">
              <th>Chore</th>
              <th>Assigned To</th>
              <th>Repeats</th>
              <th>Next Due</th>
              <th>Last Done</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={task <- @tasks} class="text-xl">
              <td class="font-semibold text-2xl">
                <span :if={task.alert} title="Chimes and reads aloud when due">&#128276;</span>{task.title}
              </td>
              <td>{if task.person, do: task.person.name, else: "-"}</td>
              <td>{recurrence_label(task.recurrence_type, task.recurrence_interval)}</td>
              <td>{format_date(task.next_date)}</td>
              <td>{format_datetime(task.last_completed_at)}</td>
              <td class="flex gap-2">
                <button
                  phx-click="mark_done"
                  phx-value-id={task.id}
                  class="btn btn-lg btn-success text-lg"
                >
                  Done
                </button>
                <button
                  phx-click="delete_event"
                  phx-value-id={task.id}
                  class="btn btn-lg btn-ghost text-error text-lg"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
