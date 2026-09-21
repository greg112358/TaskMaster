defmodule TaskmasterWeb.ChoreListLive do
  use TaskmasterWeb, :live_component

  alias Taskmaster.Clock
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

    # A component defining `update/2` assigns nothing by itself, so every key
    # the template reads has to be listed here. `@audio` is only read inside
    # the row loop, which is why an empty chore list rendered fine while the
    # first chore added took the screen down with a KeyError.
    {:ok,
     socket
     |> assign(:id, assigns.id)
     |> assign(:audio, assigns.audio)
     |> assign(:tasks, tasks_with_next)}
  end

  # The chore's own time of day rides along with the next date it falls on.
  defp format_next_due(nil, _time), do: "-"
  defp format_next_due(%Date{} = date, time), do: Clock.format_date_time(date, time)

  # `last_completed_at` is stored UTC, like every machine-written timestamp
  # here, and is read in Pacific like everything a person sees.
  defp format_completed(nil), do: "Never"
  defp format_completed(%NaiveDateTime{} = dt), do: Clock.format_datetime(dt)

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
        None
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
                <span :if={@audio and task.alert} title="Chimes and reads aloud">&#128276;</span>{task.title}
              </td>
              <td>{if task.person, do: task.person.name, else: "-"}</td>
              <td>{recurrence_label(task.recurrence_type, task.recurrence_interval)}</td>
              <td>{format_next_due(task.next_date, task.start_time)}</td>
              <td>{format_completed(task.last_completed_at)}</td>
              <td class="flex gap-2">
                <button
                  phx-click="mark_done"
                  phx-value-id={task.id}
                  class="btn btn-lg btn-success text-lg"
                >
                  Done
                </button>
                <%!-- Opens the same modal the calendar does, owned by
                      `AppLive` — this component has no state of its own. --%>
                <button
                  phx-click="edit_event"
                  phx-value-id={task.id}
                  class="btn btn-lg btn-outline text-lg"
                >
                  Edit
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
