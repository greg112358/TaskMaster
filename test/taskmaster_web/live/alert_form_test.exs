defmodule TaskmasterWeb.AlertFormTest do
  use TaskmasterWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Taskmaster.Events
  alias Taskmaster.Events.Alerts

  defp open_add_form(view, date) do
    view
    |> element("div[phx-value-date='#{Date.to_iso8601(date)}']")
    |> render_click()

    view
  end

  defp submit_add_form(view, values) do
    view
    |> form("#add-event-form", values)
    |> render_submit()

    # The component hands the params to the parent LiveView as a message;
    # rendering again waits for that message to be processed.
    render(view)
    view
  end

  describe "the alert checkbox" do
    test "the Add Event / Task form offers it", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view = isolate_view(view)

      html = view |> open_add_form(Date.utc_today()) |> render()

      assert html =~ "Chime and read aloud"
      assert html =~ ~s(name="alert")
    end

    test "checking it saves an event that will announce itself", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view = isolate_view(view)

      view
      |> open_add_form(Date.utc_today())
      |> submit_add_form(%{"title" => "water the plants", "type" => "task", "alert" => "true"})

      assert [event] = Events.list_events()
      assert event.title == "water the plants"
      assert event.alert
    end

    test "leaving it unchecked saves a silent event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view = isolate_view(view)

      view
      |> open_add_form(Date.utc_today())
      |> submit_add_form(%{"title" => "water the plants", "type" => "task"})

      assert [event] = Events.list_events()
      refute event.alert
    end
  end

  describe "the frequency field" do
    defp choose_frequency(view, type) do
      view
      |> element("#add-event-form select[name='recurrence_type']")
      |> render_change(%{"recurrence_type" => type})
    end

    test "is labelled Frequency", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view = isolate_view(view)

      html = view |> open_add_form(Date.utc_today()) |> render()

      assert html =~ "Frequency"
      refute html =~ "Repeats"
    end

    test "hides the interval field until a frequency needs one", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view = isolate_view(view)

      html = view |> open_add_form(Date.utc_today()) |> render()

      refute html =~ ~s(name="recurrence_interval")
    end

    test "keeps the interval field hidden for fixed frequencies", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view = isolate_view(view)
      open_add_form(view, Date.utc_today())

      for fixed <- ["", "daily", "weekly", "monthly", "yearly"] do
        refute choose_frequency(view, fixed) =~ ~s(name="recurrence_interval")
      end
    end

    test "shows the interval field, in the right unit, for every-N frequencies", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view = isolate_view(view)
      open_add_form(view, Date.utc_today())

      for {type, unit} <- [
            {"every_n_days", "Days"},
            {"every_n_weeks", "Weeks"},
            {"every_n_months", "Months"}
          ] do
        html = choose_frequency(view, type)

        assert html =~ ~s(name="recurrence_interval")
        # The label is the bare unit now, not a sentence.
        assert html =~ ~r{<label[^>]*>\s*#{unit}\s*</label>}
      end
    end

    test "hides the interval again when the frequency stops needing one", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view = isolate_view(view)
      open_add_form(view, Date.utc_today())

      assert choose_frequency(view, "every_n_weeks") =~ ~s(name="recurrence_interval")
      refute choose_frequency(view, "daily") =~ ~s(name="recurrence_interval")
    end

    test "saves the interval that was entered", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view = isolate_view(view)
      open_add_form(view, Date.utc_today())
      choose_frequency(view, "every_n_weeks")

      submit_add_form(view, %{
        "title" => "clean cat tree",
        "type" => "task",
        "recurrence_type" => "every_n_weeks",
        "recurrence_interval" => "2"
      })

      assert [event] = Events.list_events()
      assert event.recurrence_type == "every_n_weeks"
      assert event.recurrence_interval == 2
    end

    test "reopening the form starts back at no frequency", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view = isolate_view(view)
      open_add_form(view, Date.utc_today())
      assert choose_frequency(view, "every_n_days") =~ ~s(name="recurrence_interval")

      view |> element("button", "Cancel") |> render_click()
      html = view |> open_add_form(Date.utc_today()) |> render()

      refute html =~ ~s(name="recurrence_interval")
    end
  end

  describe "an alert coming due" do
    test "is pushed to the client to chime and read out", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view = isolate_view(view)

      Alerts.broadcast(%{
        id: 1,
        title: "clean cat tree",
        type: "task",
        person: "Greg",
        text: "Greg, time to clean cat tree"
      })

      assert_push_event(view, "alert", %{text: "Greg, time to clean cat tree"})
      assert render(view) =~ "Greg, time to clean cat tree"
    end
  end

  describe "capabilities the browser is missing" do
    test "are reported on screen rather than failing silently", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view = isolate_view(view)

      render_hook(view, "device_warning", %{
        "key" => "speech",
        "message" => "can't read alerts aloud: no voices are installed"
      })

      assert render(view) =~ "can&#39;t read alerts aloud: no voices are installed"
    end

    test "stack up rather than replacing each other", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view = isolate_view(view)

      render_hook(view, "device_warning", %{"key" => "speech", "message" => "no voices"})

      render_hook(view, "device_warning", %{"key" => "wake_lock", "message" => "screen may sleep"})

      html = render(view)
      assert html =~ "no voices"
      assert html =~ "screen may sleep"
    end

    test "clear when the hook reports the capability is back", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view = isolate_view(view)

      render_hook(view, "device_warning", %{"key" => "wake_lock", "message" => "screen may sleep"})

      assert render(view) =~ "screen may sleep"

      render_hook(view, "device_warning", %{"key" => "wake_lock", "message" => nil})
      refute render(view) =~ "screen may sleep"
    end

    test "the wake lock hook is mounted", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")
      isolate_view(view)

      assert html =~ ~s(phx-hook="WakeLock")
    end
  end

  describe "the calendar" do
    test "marks alerting events with a bell", %{conn: conn} do
      {:ok, _} =
        Events.create_event(%{
          title: "bin day",
          type: "task",
          start_date: Date.utc_today(),
          alert: true
        })

      {:ok, view, html} = live(conn, "/")
      isolate_view(view)

      assert html =~ "Chimes and reads aloud"
    end

    test "leaves silent events unmarked", %{conn: conn} do
      {:ok, _} =
        Events.create_event(%{
          title: "bin day",
          type: "task",
          start_date: Date.utc_today(),
          alert: false
        })

      {:ok, view, html} = live(conn, "/")
      isolate_view(view)

      refute html =~ "Chimes and reads aloud"
    end
  end
end
