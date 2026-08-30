# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :taskmaster,
  ecto_repos: [Taskmaster.Repo],
  generators: [timestamp_type: :utc_datetime]

# The microphone and speaker half of the board — speech recognition, speech
# synthesis, the alert chime and the scheduler behind it — behind one flag, off
# by default. See `Taskmaster.Audio`; TASKMASTER_AUDIO=1 turns it on.
config :taskmaster, audio: false

# SQLite serialises writers. Without WAL, a reader arriving mid-write fails
# outright with "database is locked" — which showed up at boot, when the
# connection pool opens alongside the embedded migrations. WAL lets readers run
# during a write; busy_timeout makes a writer wait its turn rather than erroring
# immediately.
config :taskmaster, Taskmaster.Repo,
  journal_mode: :wal,
  busy_timeout: 5_000,
  pool_size: 5,
  # SQLite has one writer by definition, so the advisory lock Ecto takes around
  # migrations buys nothing — and it costs a second connection, because the
  # lock-holding transaction waits on a Task that needs its own.
  migration_lock: false,
  # BEGIN IMMEDIATE rather than BEGIN. A deferred transaction starts as a reader
  # and takes the write lock only at its first write; if another connection got
  # there first, SQLite returns SQLITE_BUSY *immediately* and ignores
  # busy_timeout entirely, because waiting could deadlock. Taking the write lock
  # up front is what makes busy_timeout actually apply.
  transaction_mode: :immediate

# Configure the endpoint
config :taskmaster, TaskmasterWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TaskmasterWeb.ErrorHTML, json: TaskmasterWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Taskmaster.PubSub,
  live_view: [signing_salt: "UaUD2/x+"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  taskmaster: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  taskmaster: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
