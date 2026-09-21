defmodule TaskmasterWeb.ChoreListTest do
  @moduledoc """
  The Chores screen. `ChoreListLive` is presentational — no state, no
  `handle_event` — so everything here is driven through the board.
  """

  use TaskmasterWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Taskmaster.Clock
  alias Taskmaster.Events

  defp chores(conn) do
    {:ok, view, _html} = live(conn, "/")
    view = isolate_view(view)
    render_click(view, "navigate", %{"view" => "chores"})
    view
  end

  defp create_task(attrs) do
    {:ok, task} =
      Events.create_event(
        Enum.into(attrs, %{title: "Vacuum", type: "task", start_date: Clock.today()})
      )

    task
  end

  # `update/2` on a live_component assigns only what it lists, and `@audio` is
  # read only inside the row loop — so an empty list rendered while the first
  # chore added crashed the screen.
  test "renders a chore", %{conn: conn} do
    create_task(title: "Vacuum")

    html = render(chores(conn))

    assert html =~ "Vacuum"
    refute html =~ ">None<"
  end

  test "an empty list says None", %{conn: conn} do
    assert render(chores(conn)) =~ "None"
  end

  test "Next Due carries the chore's time of day", %{conn: conn} do
    create_task(title: "Feed cat", start_time: "07:00")

    assert render(chores(conn)) =~ Clock.format_date_time(Clock.today(), ~T[07:00:00])
  end

  test "an all-day chore shows a date and no time", %{conn: conn} do
    create_task(title: "Bins")

    html = render(chores(conn))

    assert html =~ Clock.format_date(Clock.today())
    refute html =~ "12:00 AM"
  end

  # Stored UTC, read Pacific — 03:15 UTC on 5 July is the evening of the 4th.
  test "Last Done is read in Pacific", %{conn: conn} do
    create_task(title: "Vacuum", last_completed_at: ~N[2026-07-05 03:15:00])

    html = render(chores(conn))

    assert html =~ "Jul 04, 2026 8:15 PM"
    refute html =~ "Jul 05"
  end

  test "a chore that has never been done says so", %{conn: conn} do
    create_task(title: "Vacuum")

    assert render(chores(conn)) =~ "Never"
  end

  test "marking one done stamps it", %{conn: conn} do
    task = create_task(title: "Vacuum")
    view = chores(conn)

    view
    |> element("button[phx-click='mark_done'][phx-value-id='#{task.id}']")
    |> render_click()

    assert Events.get_event(task.id).last_completed_at
    refute render(view) =~ "Never"
  end
end
