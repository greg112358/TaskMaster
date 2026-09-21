defmodule TaskmasterWeb.EventEditTest do
  @moduledoc """
  The Add / Edit Event modal, which both the calendar and the chore list open.

  The form and every handler behind it belong to `TaskmasterWeb.AppLive` —
  `TaskmasterWeb.EventForm` is markup — so these drive the board, not a
  component.
  """

  use TaskmasterWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Taskmaster.Clock
  alias Taskmaster.Events
  alias Taskmaster.People

  defp board(conn) do
    {:ok, view, _html} = live(conn, "/")
    isolate_view(view)
  end

  defp create_event(attrs) do
    {:ok, event} =
      Events.create_event(
        Enum.into(attrs, %{title: "Dentist", type: "event", start_date: Clock.today()})
      )

    event
  end

  defp person(name) do
    {:ok, person} = People.create_person(%{name: name})
    person
  end

  defp open_edit(view, event) do
    render_click(view, "edit_event", %{"id" => to_string(event.id)})
    view
  end

  defp save(view, values) do
    view |> form("#event-form", values) |> render_submit()
    view
  end

  describe "opening the form" do
    test "a tap on an event in the calendar opens it filled in", %{conn: conn} do
      event = create_event(title: "Dentist", start_time: "14:30")
      view = board(conn)

      html =
        view
        |> element("[phx-click='edit_event'][phx-value-id='#{event.id}']")
        |> render_click()

      assert html =~ "Edit Event / Task"
      assert html =~ ~s(value="Dentist")
      assert html =~ ~s(value="14:30")
      assert html =~ ~s(value="#{Date.to_iso8601(event.start_date)}")
    end

    test "a tap on the Edit button in the chore list opens it", %{conn: conn} do
      task = create_event(title: "Vacuum", type: "task")
      view = board(conn)

      render_click(view, "navigate", %{"view" => "chores"})

      html =
        view
        |> element("button[phx-click='edit_event'][phx-value-id='#{task.id}']")
        |> render_click()

      assert html =~ "Edit Event / Task"
      assert html =~ ~s(value="Vacuum")
      assert html =~ ~s(<option value="task" selected)
    end

    test "a tap on an empty day opens an empty form for that day", %{conn: conn} do
      view = board(conn)

      html =
        view
        |> element("div[phx-value-date='#{Date.to_iso8601(Clock.today())}']")
        |> render_click()

      assert html =~ "Add Event / Task"
      assert html =~ ~s(value="#{Date.to_iso8601(Clock.today())}")
      refute html =~ "Edit Event / Task"
    end

    test "prefills the person, the frequency and its interval", %{conn: conn} do
      greg = person("Greg")

      event =
        create_event(
          person_id: greg.id,
          recurrence_type: "every_n_weeks",
          recurrence_interval: 3
        )

      view = board(conn) |> open_edit(event)
      html = render(view)

      assert html =~ ~s(<option value="#{greg.id}" selected)
      assert html =~ ~s(<option value="every_n_weeks" selected)
      assert html =~ ~s(value="3")
    end

    # Two tablets share this board: the row can go while the finger is moving.
    test "a stale id is ignored rather than crashing the board", %{conn: conn} do
      view = board(conn)

      render_click(view, "edit_event", %{"id" => "999999"})
      render_click(view, "edit_event", %{"id" => "not-a-number"})

      refute render(view) =~ "Edit Event / Task"
      assert render(view) =~ "Calendar"
    end
  end

  describe "saving an edit" do
    test "writes the change and closes the form", %{conn: conn} do
      event = create_event(title: "Dentist")

      board(conn)
      |> open_edit(event)
      |> save(%{"title" => "Dentist, rescheduled", "start_time" => "16:15"})
      |> then(fn view -> refute render(view) =~ "Edit Event / Task" end)

      saved = Events.get_event(event.id)
      assert saved.title == "Dentist, rescheduled"
      assert saved.start_time == ~T[16:15:00]
    end

    test "moves the row to another day", %{conn: conn} do
      event = create_event([])
      moved_to = Date.add(Clock.today(), 9)

      board(conn)
      |> open_edit(event)
      |> save(%{"start_date" => Date.to_iso8601(moved_to)})

      assert Events.get_event(event.id).start_date == moved_to
    end

    test "clears a time that is emptied", %{conn: conn} do
      event = create_event(start_time: "14:30")

      board(conn)
      |> open_edit(event)
      |> save(%{"start_time" => ""})

      assert Events.get_event(event.id).start_time == nil
    end

    test "keeps the form open, and what was typed, on a rejected write", %{conn: conn} do
      event = create_event(title: "Dentist")

      html =
        board(conn)
        |> open_edit(event)
        |> save(%{"title" => "Dentist", "start_time" => "half past"})
        |> render()

      assert html =~ "Invalid field: start_time=&quot;half past&quot; (is invalid)"
      assert html =~ "Edit Event / Task"
      assert Events.get_event(event.id).title == "Dentist"
    end

    test "says so when the row has gone from under the form", %{conn: conn} do
      event = create_event([])
      view = board(conn) |> open_edit(event)

      {:ok, _} = Events.delete_event(event.id)
      save(view, %{"title" => "Dentist"})

      html = render(view)
      assert html =~ "Unknown event: #{event.id}"
      refute html =~ "Edit Event / Task"
    end
  end

  describe "changing the type" do
    test "an event becomes a chore and shows up in the chore list", %{conn: conn} do
      greg = person("Greg")

      event =
        create_event(
          title: "Water the plants",
          type: "event",
          person_id: greg.id,
          start_time: "18:00",
          recurrence_type: "every_n_days",
          recurrence_interval: 2,
          alert: true
        )

      view = board(conn) |> open_edit(event) |> save(%{"type" => "task"})

      task = Events.get_event(event.id)
      assert task.type == "task"
      # Everything else rides along: switching the type is the whole edit.
      assert task.person_id == greg.id
      assert task.start_time == ~T[18:00:00]
      assert task.recurrence_type == "every_n_days"
      assert task.recurrence_interval == 2
      assert task.alert

      render_click(view, "navigate", %{"view" => "chores"})
      html = render(view)
      assert html =~ "Water the plants"
      assert html =~ "Every 2 days"
      assert html =~ "Greg"
    end

    test "a chore becomes an event and leaves the chore list", %{conn: conn} do
      task = create_event(title: "Vacuum", type: "task")
      :ok = then(Events.mark_done(task.id), fn {:ok, _} -> :ok end)

      view = board(conn) |> open_edit(task) |> save(%{"type" => "event"})

      event = Events.get_event(task.id)
      assert event.type == "event"
      # The completion history is not thrown away by a change of type: switch
      # it back and Last Done still reads.
      assert event.last_completed_at

      render_click(view, "navigate", %{"view" => "chores"})
      html = render(view)
      refute html =~ "Vacuum"
      assert html =~ "None"
    end

    test "the calendar colours the row by its new type", %{conn: conn} do
      event = create_event(title: "Water the plants", type: "event")
      view = board(conn)

      assert render(view) =~ "bg-info/30"

      view |> open_edit(event) |> save(%{"type" => "task"})

      html = render(view)
      assert html =~ "bg-warning/30"
    end
  end

  describe "deleting from the form" do
    test "removes the row and closes the form", %{conn: conn} do
      event = create_event(title: "Dentist")
      view = board(conn) |> open_edit(event)

      view
      |> element("button[phx-click='delete_event'][phx-value-id='#{event.id}']")
      |> render_click()

      assert Events.get_event(event.id) == nil
      refute render(view) =~ "Edit Event / Task"
    end

    test "is not offered for a row that does not exist yet", %{conn: conn} do
      view = board(conn)

      html =
        view
        |> element("div[phx-value-date='#{Date.to_iso8601(Clock.today())}']")
        |> render_click()

      refute html =~ "Delete"
    end
  end

  describe "an edit made with audio off" do
    setup do
      previous = Application.get_env(:taskmaster, :audio)
      Application.put_env(:taskmaster, :audio, false)
      on_exit(fn -> Application.put_env(:taskmaster, :audio, previous) end)
      :ok
    end

    # The checkbox is not rendered with audio off, so the form sends no `alert`
    # key. Reading that as false would quietly disarm the row.
    test "leaves an alerting row armed", %{conn: conn} do
      event = create_event(title: "Dentist", alert: true)

      board(conn)
      |> open_edit(event)
      |> save(%{"title" => "Dentist"})

      assert Events.get_event(event.id).alert
    end
  end
end
