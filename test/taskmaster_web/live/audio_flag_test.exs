defmodule TaskmasterWeb.AudioFlagTest do
  @moduledoc """
  `Taskmaster.Audio` gates every part of the board that uses the microphone or
  the speakers. The suite runs with `audio: true` (config/test.exs) because it
  covers those features, so these tests put the flag back to its shipped value
  around themselves — hence `async: false`, the setting is global.
  """

  use TaskmasterWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Taskmaster.Audio
  alias Taskmaster.Events

  defp set_audio(value) do
    previous = Application.get_env(:taskmaster, :audio)
    Application.put_env(:taskmaster, :audio, value)
    on_exit(fn -> Application.put_env(:taskmaster, :audio, previous) end)
  end

  defp board(conn) do
    {:ok, view, _html} = live(conn, "/")
    isolate_view(view)
  end

  defp open_add_form(view) do
    view
    |> element("div[phx-value-date='#{Date.to_iso8601(Date.utc_today())}']")
    |> render_click()

    view
  end

  describe "the flag itself" do
    test "is off unless configured on" do
      previous = Application.get_env(:taskmaster, :audio)
      Application.delete_env(:taskmaster, :audio)
      on_exit(fn -> Application.put_env(:taskmaster, :audio, previous) end)

      refute Audio.enabled?()
    end

    test "reads the config" do
      set_audio(true)
      assert Audio.enabled?()

      Application.put_env(:taskmaster, :audio, false)
      refute Audio.enabled?()
    end
  end

  describe "with audio off" do
    setup do
      set_audio(false)
      :ok
    end

    test "the page carries no VoiceRecognition hook", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      refute html =~ "VoiceRecognition"
    end

    test "the voice hint bar is gone", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      refute html =~ "Try saying:"
      refute html =~ "add milk to groceries"
    end

    test "the Add Event / Task form offers no alert checkbox or Test button", %{conn: conn} do
      html = conn |> board() |> open_add_form() |> render()

      refute html =~ "Chime and read aloud"
      refute html =~ ~s(name="alert")
      refute html =~ "taskmaster:test-alert"
    end

    test "an already-alerting event shows no bell", %{conn: conn} do
      {:ok, _event} =
        Events.create_event(%{
          title: "bin day",
          type: "task",
          start_date: Date.utc_today(),
          recurrence_type: "weekly",
          alert: true
        })

      html = conn |> board() |> render()

      refute html =~ "Chimes and reads aloud"
    end

    test "a due alert is not pushed to a board that cannot sound it", %{conn: conn} do
      view = board(conn)

      Taskmaster.Events.Alerts.broadcast(%{id: 1, title: "bin day", text: "Time to bin day"})

      # The view is not subscribed, so the banner never appears.
      refute render(view) =~ "Time to bin day"
    end
  end

  describe "with audio on" do
    setup do
      set_audio(true)
      :ok
    end

    test "the page carries the VoiceRecognition hook", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ ~s(phx-hook="VoiceRecognition")
      assert html =~ "Try saying:"
    end

    test "the Add Event / Task form offers the alert checkbox", %{conn: conn} do
      html = conn |> board() |> open_add_form() |> render()

      assert html =~ "Chime and read aloud"
    end
  end
end
