defmodule Taskmaster.EventTest do
  use Taskmaster.DataCase, async: false

  alias Taskmaster.Events
  alias Taskmaster.Events.Event
  alias Taskmaster.Events.Recurrence

  defp attrs(overrides) do
    Enum.into(overrides, %{
      title: "Water the plants",
      type: "task",
      start_date: ~D[2026-01-01]
    })
  end

  describe "the recurrence interval" do
    # `Recurrence.occurrences_in_range/3` only terminates while `next_date/2`
    # advances. An interval of zero or less never advances, and because the rule
    # is stored, every later render of the calendar hangs the same way.
    test "zero is rejected" do
      changeset =
        Event.changeset(%Event{}, attrs(recurrence_type: "every_n_days", recurrence_interval: 0))

      refute changeset.valid?
      assert %{recurrence_interval: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "a negative interval is rejected" do
      changeset =
        Event.changeset(
          %Event{},
          attrs(recurrence_type: "every_n_weeks", recurrence_interval: -3)
        )

      refute changeset.valid?
      assert %{recurrence_interval: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "a rule that counts in intervals must carry one" do
      changeset =
        Event.changeset(
          %Event{},
          attrs(recurrence_type: "every_n_months", recurrence_interval: nil)
        )

      refute changeset.valid?
      assert %{recurrence_interval: ["can't be blank"]} = errors_on(changeset)
    end

    test "a rule that does not is left alone" do
      changeset =
        Event.changeset(%Event{}, attrs(recurrence_type: "weekly", recurrence_interval: nil))

      assert changeset.valid?
    end

    test "a positive interval is accepted" do
      changeset =
        Event.changeset(%Event{}, attrs(recurrence_type: "every_n_days", recurrence_interval: 2))

      assert changeset.valid?
    end
  end

  describe "the recurrence type" do
    test "an unknown rule is rejected" do
      changeset = Event.changeset(%Event{}, attrs(recurrence_type: "fortnightly"))

      refute changeset.valid?
      assert %{recurrence_type: ["is invalid"]} = errors_on(changeset)
    end

    test "no rule at all is a one-time event" do
      changeset = Event.changeset(%Event{}, attrs(recurrence_type: nil))
      assert changeset.valid?
    end

    test "every rule the calendar offers is accepted" do
      for type <- Event.recurrence_types() do
        changeset =
          Event.changeset(%Event{}, attrs(recurrence_type: type, recurrence_interval: 1))

        assert changeset.valid?, "#{type} was rejected"
      end
    end
  end

  describe "the guard behind the validation" do
    # Belt and braces for a row written before the validation existed: raising is
    # recoverable, an endless stream is not.
    test "a bad interval raises instead of looping forever" do
      event = %Event{
        start_date: ~D[2026-01-01],
        recurrence_type: "every_n_days",
        recurrence_interval: 0
      }

      task =
        Task.async(fn ->
          try do
            Recurrence.occurrences_in_range(event, ~D[2026-08-29], ~D[2026-08-29])
            :returned
          rescue
            FunctionClauseError -> :raised
          end
        end)

      assert Task.yield(task, 2_000) == {:ok, :raised},
             "occurrences_in_range/3 did not terminate"
    end
  end

  describe "writes" do
    test "the interval cannot reach the database" do
      assert {:error, changeset} =
               Events.create_event(attrs(recurrence_type: "every_n_days", recurrence_interval: 0))

      assert %{recurrence_interval: _} = errors_on(changeset)
      assert Events.list_events() == []
    end
  end
end
