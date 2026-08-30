defmodule Taskmaster.Events.AlertsTest do
  use Taskmaster.DataCase

  alias Taskmaster.Events
  alias Taskmaster.Events.Alerts
  alias Taskmaster.People

  @today ~D[2026-08-26]

  defp event(attrs) do
    {:ok, event} =
      Events.create_event(
        Enum.into(attrs, %{title: "clean cat tree", type: "task", start_date: @today})
      )

    event
  end

  defp person(name) do
    {:ok, person} = People.create_person(%{name: name})
    person
  end

  describe "due_on/1" do
    test "returns an alerting event scheduled for that day" do
      due = event(alert: true)
      assert [%{id: id}] = Alerts.due_on(@today)
      assert id == due.id
    end

    test "ignores events with the alert checkbox off" do
      event(alert: false)
      assert Alerts.due_on(@today) == []
    end

    test "ignores events scheduled for another day" do
      event(alert: true, start_date: Date.add(@today, 1))
      assert Alerts.due_on(@today) == []
    end

    test "follows the recurrence rule rather than the start date" do
      weekly = event(alert: true, start_date: Date.add(@today, -14), recurrence_type: "weekly")

      assert [%{id: id}] = Alerts.due_on(@today)
      assert id == weekly.id
      assert Alerts.due_on(Date.add(@today, 1)) == []
    end

    test "ignores an event that already announced today" do
      due = event(alert: true)
      {:ok, _} = Alerts.mark_alerted(due, @today)

      assert Alerts.due_on(@today) == []
    end

    test "an event that announced yesterday is due again today" do
      daily = event(alert: true, recurrence_type: "daily", start_date: Date.add(@today, -3))
      {:ok, _} = Alerts.mark_alerted(daily, Date.add(@today, -1))

      assert [%{id: id}] = Alerts.due_on(@today)
      assert id == daily.id
    end
  end

  describe "fire_due/1" do
    setup do
      Alerts.subscribe()
      :ok
    end

    test "broadcasts a payload for each due alert" do
      event(alert: true)

      assert [payload] = Alerts.fire_due(@today)
      assert payload.text == "Time to clean cat tree"
      assert_receive {:alert, ^payload}
    end

    test "announces once per day even if polled repeatedly" do
      event(alert: true)

      assert [_payload] = Alerts.fire_due(@today)
      assert Alerts.fire_due(@today) == []
      assert Alerts.fire_due(@today) == []
    end

    test "announces again on the next occurrence" do
      event(alert: true, recurrence_type: "daily")

      assert [_] = Alerts.fire_due(@today)
      assert [_] = Alerts.fire_due(Date.add(@today, 1))
    end

    test "records the day it announced" do
      due = event(alert: true)
      Alerts.fire_due(@today)

      assert Events.get_event!(due.id).last_alerted_on == @today
    end

    test "does not announce anything when nothing is due" do
      event(alert: false)

      assert Alerts.fire_due(@today) == []
      # fire_due/1 broadcasts before it returns, so there is nothing in flight
      # to wait for — the default 100ms timeout only ever waited.
      refute_received {:alert, _}
    end
  end

  describe "announcement/1" do
    test "phrases an unassigned task as an instruction" do
      assert Alerts.announcement(event(alert: true)) == "Time to clean cat tree"
    end

    test "names the person a task is assigned to" do
      greg = person("Greg")
      task = event(alert: true, person_id: greg.id) |> Repo.preload(:person)

      assert Alerts.announcement(task) == "Greg, time to clean cat tree"
    end

    test "phrases an event as a heads-up" do
      birthday = event(type: "event", title: "Cat's Birthday", alert: true)

      assert Alerts.announcement(birthday) == "Today: Cat's Birthday"
    end

    test "names the person an event belongs to" do
      greg = person("Greg")

      birthday =
        event(type: "event", title: "Dentist", alert: true, person_id: greg.id)
        |> Repo.preload(:person)

      assert Alerts.announcement(birthday) == "Today: Dentist, for Greg"
    end

    test "treats an unloaded person as no person" do
      greg = person("Greg")
      task = event(alert: true, person_id: greg.id)

      assert Alerts.announcement(task) == "Time to clean cat tree"
    end
  end

  describe "payload/1" do
    test "carries what the client needs to display and speak the alert" do
      greg = person("Greg")
      task = event(alert: true, person_id: greg.id) |> Repo.preload(:person)

      assert Alerts.payload(task) == %{
               id: task.id,
               title: "clean cat tree",
               type: "task",
               person: "Greg",
               text: "Greg, time to clean cat tree"
             }
    end
  end
end
