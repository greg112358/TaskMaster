defmodule Taskmaster.Events do
  import Ecto.Query
  alias Taskmaster.Clock
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

  # Untimed rows first, then by time: SQLite sorts NULL before any value in an
  # ascending order, which is the order a day's column should read in.
  def list_events do
    Repo.all(
      from e in Event,
        preload: [:person],
        order_by: [asc: e.start_date, asc: e.start_time]
    )
  end

  def list_tasks do
    Repo.all(
      from e in Event,
        where: e.type == "task",
        preload: [:person],
        order_by: [asc: e.start_date, asc: e.start_time]
    )
  end

  def get_event!(id), do: Repo.get!(Event, id) |> Repo.preload(:person)

  @doc "The event, or `nil` when the id is stale. Use this for ids off the wire."
  def get_event(id) do
    case Repo.get(Event, id) do
      nil -> nil
      event -> Repo.preload(event, :person)
    end
  end

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
  Applies an edit to an existing event or chore, including a change of `type`
  in either direction — the column is the only thing separating the two, so
  nothing else has to move with it.

  `:error` when the id is stale, as for `mark_done/1`: the row can go under the
  finger of whoever is holding the other tablet while the form is open.
  """
  def update_event(id, attrs) do
    case Repo.get(Event, id) do
      nil ->
        :error

      event ->
        event
        |> Event.changeset(attrs)
        |> Repo.update()
        |> tap(fn
          {:ok, _} -> broadcast()
          _ -> :ok
        end)
    end
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
    # Erlang term order sorts a %Date{} by its keys alphabetically — day before
    # month before year — so both halves of the key are converted first. An
    # all-day row has no time and sorts ahead of the timed ones, since nil is an
    # atom and atoms precede tuples.
    |> Enum.sort_by(fn {date, event} ->
      {Date.to_erl(date), event.start_time && Time.to_erl(event.start_time)}
    end)
  end

  def next_occurrence(%Event{} = event) do
    today = Clock.today()
    Recurrence.next_occurrence_from(event, today)
  end
end
