defmodule TaskmasterWeb.ChoreFilterTest do
  @moduledoc """
  The calendar's "Hide chores" toggle. `CalendarLive` has no `handle_event` of
  its own — the click bubbles to `AppLive`, which `send_update`s the
  component — and the toggle's own state is driven the same way regardless of
  whether it originated from a click or from `ChoreFilter`'s localStorage
  sync (`assets/js/hooks/chore_filter.js`).
  """

  use TaskmasterWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Taskmaster.Clock
  alias Taskmaster.Events

  defp board(conn) do
    {:ok, view, _html} = live(conn, "/")
    isolate_view(view)
  end

  defp create_task(attrs) do
    {:ok, task} =
      Events.create_event(
        Enum.into(attrs, %{title: "Vacuum", type: "task", start_date: Clock.today()})
      )

    task
  end

  defp create_event(attrs) do
    {:ok, event} =
      Events.create_event(
        Enum.into(attrs, %{title: "Dentist", type: "event", start_date: Clock.today()})
      )

    event
  end

  # The toggle click bubbles to `AppLive`, which `send_update`s the
  # component — a message to the view's own mailbox, processed *after*
  # `handle_event` returns. `render_click/3`'s reply can land before that
  # second message is handled, so a settling render (same idiom as
  # `grocery_dictionary_test.exs`'s `settle/1`) gets the DOM caught up.
  defp settle(view) do
    Enum.each(1..3, fn _ -> render(view) end)
    render(view)
  end

  test "chores show on the calendar by default", %{conn: conn} do
    create_task(%{})

    html = board(conn) |> render()
    assert html =~ "Vacuum"
  end

  test "toggling the switch hides chores but not events", %{conn: conn} do
    create_task(%{})
    create_event(%{})

    view = board(conn)
    render_click(view, "calendar_toggle_chores", %{})
    html = settle(view)

    refute html =~ "Vacuum"
    assert html =~ "Dentist"
  end

  test "toggling twice shows chores again", %{conn: conn} do
    create_task(%{})

    view = board(conn)
    render_click(view, "calendar_toggle_chores", %{})
    settle(view)
    render_click(view, "calendar_toggle_chores", %{})
    html = settle(view)

    assert html =~ "Vacuum"
  end

  test "restore_hide_chores (the localStorage sync) hides chores without a click", %{conn: conn} do
    create_task(%{})

    view = board(conn)
    render_click(view, "restore_hide_chores", %{"hide" => true})
    html = settle(view)

    refute html =~ "Vacuum"
  end
end
