defmodule Taskmaster.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Ensure config dir and ETS session table exist
    File.mkdir_p!(config_dir())
    :ets.new(:session, [:named_table, :public, read_concurrency: true])

    # Configure SQLite database path. `put_new` so an explicitly configured
    # database (e.g. `:memory:` in config/test.exs) is left alone, and so the
    # rest of the Repo config (pool, pool_size, ...) survives.
    Application.put_env(
      :taskmaster,
      Taskmaster.Repo,
      Application.get_env(:taskmaster, Taskmaster.Repo, [])
      |> Keyword.put_new(:database, Path.join(config_dir(), "taskmaster.db"))
    )

    children = [
      TaskmasterWeb.Telemetry,
      Taskmaster.Repo,
      {Phoenix.PubSub, name: Taskmaster.PubSub},
      TaskmasterWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Taskmaster.Supervisor]
    {:ok, sup} = Supervisor.start_link(children, opts)

    # Run embedded migrations
    Taskmaster.Repo.Migrator.run()

    # The alert scheduler queries the events table, so it is started as a child
    # only after the embedded migrations above have run.
    if Application.get_env(:taskmaster, :alert_scheduler, true) do
      {:ok, _} = Supervisor.start_child(sup, Taskmaster.Events.AlertScheduler)
    end

    # Start Desktop window (disabled in :test, see config/test.exs)
    if Application.get_env(:taskmaster, :desktop_window, true) do
      {:ok, _} =
        Supervisor.start_child(sup, {
          Desktop.Window,
          [
            app: :taskmaster,
            id: TaskmasterWindow,
            title: "Taskmaster",
            size: {1024, 600},
            url: &TaskmasterWeb.Endpoint.url/0
          ]
        })
    end

    {:ok, sup}
  end

  @impl true
  def config_change(changed, _new, removed) do
    TaskmasterWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp config_dir do
    Path.join(System.user_home!(), ".config/taskmaster")
  end
end
