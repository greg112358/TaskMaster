import Config

# SQLite is configured at runtime in application.ex

# For development, we disable any cache and enable
# debugging and code reloading.
config :taskmaster, TaskmasterWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 0],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  server: true,
  secret_key_base: "/ktRbDILOzhX9KU9Kg/UA4+uXszIdD5BAijwbUnegptPHVM7hL48i6jv5+TpALaJ",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:taskmaster, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:taskmaster, ~w(--watch)]}
  ]

# Reload browser tabs when matching files change.
config :taskmaster, TaskmasterWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
      ~r"priv/gettext/.*\.po$"E,
      ~r"lib/taskmaster_web/router\.ex$"E,
      ~r"lib/taskmaster_web/(controllers|live|components)/.*\.(ex|heex)$"E
    ]
  ]

config :taskmaster, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
