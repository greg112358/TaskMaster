defmodule Taskmaster.EventTimeTest do
  @moduledoc """
  `start_time` is the wall-clock time an event happens, Pacific like everything
  else (`Taskmaster.Clock`), and `nil` for an all-day row.
  """

  use Taskmaster.DataCase, async: false

  alias Taskmaster.Events
  alias Taskmaster.Events.Event

  defp attrs(overrides) do
    Enum.into(overrides, %{title: "Dentist", type: "event", start_date: ~D[2026-01-01]})
  end

  defp create(overrides) do
    {:ok, event} = Events.create_event(attrs(overrides))
    event
  end

  describe "the time on an event" do
    test "is optional — no time is an all-day row" do
      assert create([]).start_time == nil
    end

    test "casts what `<input type=\"time\">` sends" do
      assert create(start_time: "14:30").start_time == ~T[14:30:00]
      assert create(start_time: "09:00:00").start_time == ~T[09:00:00]
    end

    test "is cleared by an empty field" do
      event = create(start_time: "14:30")

      assert {:ok, updated} = Events.update_event(event.id, attrs(start_time: nil))
      assert updated.start_time == nil
    end

    test "is refused rather than raised on for anything else" do
      changeset = Event.changeset(%Event{}, attrs(start_time: "half past"))

      refute changeset.valid?
      assert %{start_time: ["is invalid"]} = errors_on(changeset)
    end

    # SQLite keeps a time as text, so "09:00:00.000000" and "09:00:00" would
    # order against each other as strings.
    test "is stored to the second" do
      event = create(start_time: ~T[09:00:00.123456])

      assert event.start_time == ~T[09:00:00]
      assert Events.get_event(event.id).start_time == ~T[09:00:00]
    end
  end

  describe "the order a day reads in" do
    test "puts all-day rows first, then the timed ones by time" do
      create(title: "Dentist", start_time: "14:30")
      create(title: "School run", start_time: "08:15")
      create(title: "Bin day")

      assert ["Bin day", "School run", "Dentist"] = Enum.map(Events.list_events(), & &1.title)
    end

    test "holds for the chore list too" do
      create(title: "Vacuum", type: "task", start_time: "18:00")
      create(title: "Feed cat", type: "task", start_time: "07:00")

      assert ["Feed cat", "Vacuum"] = Enum.map(Events.list_tasks(), & &1.title)
    end
  end
end
