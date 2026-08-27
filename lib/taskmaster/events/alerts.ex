defmodule Taskmaster.Events.Alerts do
  @moduledoc """
  Due-alert detection and announcement text for events and tasks.

  An event with `alert: true` announces itself — a chime followed by the title
  read aloud — on the day it is due. `last_alerted_on` records the day it last
  announced, so each occurrence announces exactly once even if the app is
  restarted during the day.

  The sound itself is produced in the browser/webview. The chain is:

      AlertScheduler (polls)
        -> Alerts.fire_due/1 marks + broadcasts {:alert, payload} on "alerts"
        -> TaskmasterWeb.AppLive forwards it with push_event("alert", payload)
        -> the VoiceRecognition JS hook plays the chime and speaks payload.text

  Missed days are not replayed: if the app is off on the day something was due,
  that occurrence is skipped rather than announced late.
  """

  import Ecto.Query

  alias Taskmaster.People.Person
  alias Taskmaster.Repo
  alias Taskmaster.Events.Event
  alias Taskmaster.Events.Recurrence

  @topic "alerts"

  def subscribe do
    Phoenix.PubSub.subscribe(Taskmaster.PubSub, @topic)
  end

  def broadcast(payload) do
    Phoenix.PubSub.broadcast(Taskmaster.PubSub, @topic, {:alert, payload})
  end

  @doc """
  Events/tasks with alerts enabled that occur on `date` and have not already
  announced on that day.
  """
  def due_on(date \\ Date.utc_today()) do
    from(e in Event,
      where: e.alert == true,
      where: is_nil(e.last_alerted_on) or e.last_alerted_on < ^date,
      order_by: [asc: e.id],
      preload: [:person]
    )
    |> Repo.all()
    |> Enum.filter(&occurs_on?(&1, date))
  end

  @doc """
  Announces everything due on `date`: marks each event as alerted and
  broadcasts its payload. Returns the payloads that were broadcast.

  Marking happens before the broadcast, so a crash in a subscriber cannot cause
  the same alert to fire again on the next poll.
  """
  def fire_due(date \\ Date.utc_today()) do
    date
    |> due_on()
    |> Enum.flat_map(fn event ->
      case mark_alerted(event, date) do
        {:ok, _event} ->
          payload = payload(event)
          broadcast(payload)
          [payload]

        {:error, _changeset} ->
          []
      end
    end)
  end

  def mark_alerted(%Event{} = event, date \\ Date.utc_today()) do
    event
    |> Event.changeset(%{last_alerted_on: date})
    |> Repo.update()
  end

  @doc """
  The payload handed to the client. `:text` is what gets spoken; the other
  fields are there for on-screen display.
  """
  def payload(%Event{} = event) do
    %{
      id: event.id,
      title: event.title,
      type: event.type,
      person: person_name(event),
      text: announcement(event)
    }
  end

  @doc """
  The sentence read aloud. Tasks are phrased as an instruction, events as a
  heads-up.
  """
  def announcement(%Event{} = event) do
    case {event.type, person_name(event)} do
      {"task", nil} -> "Time to #{event.title}"
      {"task", name} -> "#{name}, time to #{event.title}"
      {_type, nil} -> "Today: #{event.title}"
      {_type, name} -> "Today: #{event.title}, for #{name}"
    end
  end

  defp occurs_on?(%Event{} = event, date) do
    Recurrence.occurrences_in_range(event, date, date) != []
  end

  # `person` is only a %Person{} when it has been preloaded and is set.
  defp person_name(%Event{person: %Person{name: name}}), do: name
  defp person_name(%Event{}), do: nil
end
