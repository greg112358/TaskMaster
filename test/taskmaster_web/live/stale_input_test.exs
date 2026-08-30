defmodule TaskmasterWeb.StaleInputTest do
  @moduledoc """
  Ids and dates reaching `AppLive` come from the client, so they can be stale —
  two tablets share this board, and a double-tap outruns the re-render — or
  simply not a number. None of it may take the view down: a crash on a wall
  appliance is a flash and a lost modal, with no console to explain it.
  """

  use TaskmasterWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Taskmaster.Events
  alias Taskmaster.Grocery

  @gone 999_999

  defp board(conn) do
    {:ok, view, _html} = live(conn, "/")
    isolate_view(view)
  end

  describe "the contexts" do
    test "report a stale id rather than raising" do
      assert Events.mark_done(@gone) == :error
      assert Events.delete_event(@gone) == :error
      assert Grocery.toggle_item(@gone) == :error
      assert Grocery.delete_item(@gone) == :error
    end
  end

  describe "the board" do
    test "survives a tap on a row that has already gone", %{conn: conn} do
      view = board(conn)

      render_click(view, "mark_done", %{"id" => to_string(@gone)})
      render_click(view, "delete_event", %{"id" => to_string(@gone)})
      render_click(view, "toggle_grocery", %{"id" => to_string(@gone)})
      render_click(view, "delete_grocery", %{"id" => to_string(@gone)})
      render_click(view, "delete_person", %{"id" => to_string(@gone)})

      assert render(view) =~ "Calendar"
    end

    test "survives an id that is not a number", %{conn: conn} do
      view = board(conn)

      render_click(view, "delete_grocery", %{"id" => "12abc"})
      render_click(view, "mark_done", %{"id" => ""})

      assert render(view) =~ "Calendar"
    end

    test "survives an unparseable start date", %{conn: conn} do
      view = board(conn)

      render_click(view, "add_event", %{"title" => "Dentist", "start_date" => "soon"})

      assert render(view) =~ "Invalid field: start_date=&quot;soon&quot; (not a date)"
      assert Events.list_events() == []
    end
  end

  describe "a rejected event" do
    test "says so instead of closing on nothing", %{conn: conn} do
      view = board(conn)

      render_click(view, "add_event", %{
        "title" => "Bins out",
        "type" => "task",
        "start_date" => Date.to_iso8601(Date.utc_today()),
        "recurrence_type" => "every_n_days",
        "recurrence_interval" => "0"
      })

      assert render(view) =~
               "Invalid field: recurrence_interval=0 (must be greater than 0)"

      assert Events.list_events() == []
    end
  end
end
