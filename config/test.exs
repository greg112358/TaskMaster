import Config

# SQLite test database.
#
# A file rather than `:memory:`, because the schema has to survive across
# connections — and there are at least two, since Ecto always runs a migration
# inside a Task and the caller holds a connection while it waits.
#
# WAL is off here even though production uses it: under WAL a write-write
# collision returns SQLITE_BUSY immediately rather than honouring busy_timeout,
# and a LiveView still finishing work as one test ends will collide with the
# next test's connection. The rollback journal waits instead, which is what
# makes the suite deterministic.
config :taskmaster, Taskmaster.Repo,
  database: Path.expand("../taskmaster_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 2,
  journal_mode: :delete

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
#
# `audio: true` deviates from the shipped default, which is off: the suite
# covers the voice and alert features, so it runs with them on. The tests for
# the flag itself (test/taskmaster_web/live/audio_flag_test.exs) put it back to
# false around themselves.
config :taskmaster,
  desktop_window: false,
  alert_scheduler: false,
  audio: true

# A fixture rather than the real credentials.txt, so the suite neither depends
# on nor reads the developer's own login.
config :taskmaster,
  credentials_path: Path.expand("../test/support/credentials.txt", __DIR__)
