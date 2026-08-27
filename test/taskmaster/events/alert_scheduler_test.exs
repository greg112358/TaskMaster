defmodule Taskmaster.Events.AlertSchedulerTest do
  use Taskmaster.DataCase

  alias Taskmaster.Events
  alias Taskmaster.Events.AlertScheduler
  alias Taskmaster.Events.Alerts

  # The scheduler always polls for "today", so fixtures are dated accordingly.
  defp due_task(attrs \\ []) do
    {:ok, event} =
      Events.create_event(
        Enum.into(attrs, %{
          title: "take out the bins",
          type: "task",
          start_date: Date.utc_today(),
          alert: true
        })
      )

    event
  end

  defp start_scheduler(opts) do
    start_supervised!(
      {AlertScheduler,
       Keyword.merge([name: :test_alert_scheduler, tick_interval: :timer.hours(1)], opts)}
    )

    :test_alert_scheduler
  end

  setup do
    Alerts.subscribe()
    :ok
  end

  test "check_now announces what is due and does not repeat it" do
    scheduler = start_scheduler(watch_events: false)
    task = due_task()

    assert [payload] = AlertScheduler.check_now(scheduler)
    assert payload.id == task.id
    assert payload.text == "Time to take out the bins"
    assert_receive {:alert, ^payload}

    assert AlertScheduler.check_now(scheduler) == []
  end

  test "saving an event due today announces it without waiting for the next tick" do
    start_scheduler(watch_events: true)

    due_task(title: "feed the cat")

    assert_receive {:alert, %{text: "Time to feed the cat"}}, 1000
  end

  test "saving an event that is not due stays quiet" do
    start_scheduler(watch_events: true)

    due_task(start_date: Date.add(Date.utc_today(), 3))

    refute_receive {:alert, _}, 200
  end

  test "the first poll waits a tick so it does not fire before a client connects" do
    start_scheduler(watch_events: false, tick_interval: :timer.hours(1))
    due_task()

    refute_receive {:alert, _}, 200
  end

  test "a tick announces what is due" do
    start_scheduler(watch_events: false, tick_interval: 50)
    due_task()

    assert_receive {:alert, %{text: "Time to take out the bins"}}, 1000
  end

  test "check_now on a scheduler that is not running returns no alerts" do
    assert AlertScheduler.check_now(:no_such_alert_scheduler) == []
  end
end
