defmodule Taskmaster.Events.AlertScheduler do
  @moduledoc """
  Polls for due alerts and announces them (see `Taskmaster.Events.Alerts`).

  Two things wake it up:

    * a timer, every `#{div(:timer.seconds(30), 1000)}` seconds, which is what
      catches the rollover into a new day on a board that is left running; and
    * the `:events_changed` broadcast, so an event saved with "chime and read
      aloud" checked for *today* announces right away instead of up to a tick
      later.

  The first poll is deliberately one tick after boot rather than immediate:
  announcing before the desktop window has connected its LiveView would mark
  the alert as fired with nobody listening.

  Started by `Taskmaster.Application` after the embedded migrations have run.
  Set `config :taskmaster, alert_scheduler: false` to skip starting it (the
  test environment does this and drives `Alerts` directly).

  ## Options

    * `:name` - registered name, defaults to the module name
    * `:tick_interval` - milliseconds between polls
    * `:watch_events` - subscribe to `:events_changed`, defaults to `true`
  """

  use GenServer

  require Logger

  alias Taskmaster.Events
  alias Taskmaster.Events.Alerts

  @tick_interval :timer.seconds(30)

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Polls immediately instead of waiting for the next tick and returns the
  payloads announced. Returns `[]` if the scheduler is not running.
  """
  def check_now(server \\ __MODULE__) do
    GenServer.call(server, :check)
  catch
    :exit, _reason -> []
  end

  @impl true
  def init(opts) do
    if Keyword.get(opts, :watch_events, true), do: Events.subscribe()

    interval = Keyword.get(opts, :tick_interval, @tick_interval)
    schedule_tick(interval)

    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_call(:check, _from, state) do
    {:reply, check(), state}
  end

  @impl true
  def handle_info(:tick, state) do
    check()
    schedule_tick(state.interval)
    {:noreply, state}
  end

  def handle_info(:events_changed, state) do
    check()
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # A failed poll (database busy, say) must not take the scheduler down with
  # it — the next tick will try again.
  defp check do
    Alerts.fire_due(Date.utc_today())
  rescue
    error ->
      Logger.warning("Alert check failed: #{Exception.message(error)}")
      []
  end

  defp schedule_tick(interval), do: Process.send_after(self(), :tick, interval)
end
