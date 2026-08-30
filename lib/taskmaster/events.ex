defmodule Taskmaster.Events do
  import Ecto.Query
  alias Taskmaster.Repo
  alias Taskmaster.Events.Event
  alias Taskmaster.Events.Recurrence

  @topic "events"

  def subscribe do
    Phoenix.PubSub.subscribe(Taskmaster.PubSub, @topic)
  end

  defp broadcast do
    Phoenix.PubSub.broadcast(Taskmaster.PubSub, @topic, :events_changed)
  end

  def list_events do
    Repo.all(from e in Event, preload: [:person], order_by: [asc: e.start_date])
  end

  def list_tasks do
    Repo.all(
      from e in Event,
        where: e.type == "task",
        preload: [:person],
        order_by: [asc: e.start_date]
    )
  end

  def get_event!(id), do: Repo.get!(Event, id) |> Repo.preload(:person)

  def create_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
    |> tap(fn
      {:ok, _} -> broadcast()
      _ -> :ok
    end)
  end

  @doc """
  Records a chore as done. `:error` when the id is stale — a double-tap, or the
  other tablet having deleted the row first, is not worth crashing the board for.
  """
  def mark_done(id) do
    case Repo.get(Event, id) do
      nil ->
        :error

      event ->
        event
        |> Event.changeset(%{last_completed_at: NaiveDateTime.utc_now()})
        |> Repo.update()
        |> tap(fn
          {:ok, _} -> broadcast()
          _ -> :ok
        end)
    end
  end

  @doc "Removes an event or chore. `:error` when the id is stale — see `mark_done/1`."
  def delete_event(id) do
    case Repo.get(Event, id) do
      nil ->
        :error

      event ->
        event
        |> Repo.delete()
        |> tap(fn
          {:ok, _} -> broadcast()
          _ -> :ok
        end)
    end
  end

  def events_in_range(range_start, range_end) do
    events = list_events()

    Enum.flat_map(events, fn event ->
      dates = Recurrence.occurrences_in_range(event, range_start, range_end)
      Enum.map(dates, fn date -> {date, event} end)
    end)
    |> Enum.sort_by(fn {date, _} -> date end, Date)
  end

  def next_occurrence(%Event{} = event) do
    today = Date.utc_today()
    Recurrence.next_occurrence_from(event, today)
  end
end
