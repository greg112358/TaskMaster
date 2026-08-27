import Config

# SQLite test database. A file rather than `:memory:` because an in-memory
# SQLite database forces pool_size: 1, and the embedded migrations that
# Taskmaster.Application runs at boot need a second connection (Ecto runs them
# from a Task), which deadlocks a single-connection pool.
config :taskmaster, Taskmaster.Repo,
  database: Path.expand("../taskmaster_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :taskmaster, TaskmasterWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "77/XfFuPb6EwDBAaOBNkBz8cX0KccSAtuW+5Ef2wn6thGz1kur5RtTCpAwjMJKaP",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix,
  sort_verified_routes_query_params: true

# No wx desktop window during tests, and no background alert polling (tests
# drive Taskmaster.Events.Alerts directly, or start their own scheduler).
config :taskmaster,
  desktop_window: false,
  alert_scheduler: false
