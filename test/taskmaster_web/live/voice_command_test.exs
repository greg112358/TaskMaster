defmodule TaskmasterWeb.VoiceCommandTest do
  @moduledoc """
  What a spoken command writes, and what the status bar says back. The parsing
  itself is covered in `Taskmaster.Voice.ParserTest`.
  """

  use TaskmasterWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Taskmaster.Clock
  alias Taskmaster.Events
  alias Taskmaster.People

  defp board(conn) do
    {:ok, view, _html} = live(conn, "/")
    isolate_view(view)
  end

  defp say(view, transcript) do
    render_hook(view, "voice_command", %{"transcript" => transcript})

    # The write broadcasts, and the reload that lands on the broadcast runs
    # *after* the hook has replied. A second round trip is answered only once
    # everything already queued has run, so nothing is still reading the
    # database when the test ends and the sandbox connection moves on.
    render(view)
  end

  test "an event with a time is added for today at that time", %{conn: conn} do
    html = board(conn) |> say("add event dentist at 3pm")

    assert [event] = Events.list_events()
    assert event.title == "dentist"
    assert event.type == "event"
    assert event.start_date == Clock.today()
    assert event.start_time == ~T[15:00:00]
    assert html =~ "Added event: dentist (3:00 PM)"
  end

  test "a chore with a time and an assignee names both back", %{conn: conn} do
    {:ok, _greg} = People.create_person(%{name: "Greg"})

    html = board(conn) |> say("add task for greg bins at 7 am every week")

    assert [task] = Events.list_tasks()
    assert task.start_time == ~T[07:00:00]
    assert task.recurrence_type == "weekly"
    assert html =~ "Added task: bins (Greg, 7:00 AM)"
  end

  test "a chore with neither is reported plainly", %{conn: conn} do
    html = board(conn) |> say("add task vacuum")

    assert [task] = Events.list_tasks()
    assert task.title == "vacuum"
    assert html =~ "Added task: vacuum"
  end

  test "a name nobody on the board has is refused by name", %{conn: conn} do
    html = board(conn) |> say("add task for bob vacuum")

    assert Events.list_events() == []
    assert html =~ "Unknown person: bob"
  end

  test "anything unparsed answers I missed that", %{conn: conn} do
    view = board(conn)

    assert say(view, "what is the weather") =~ "I missed that"
    assert_push_event(view, "speak", %{text: "I missed that"})
  end
end
