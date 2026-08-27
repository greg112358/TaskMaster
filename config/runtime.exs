import Config

# Runtime config.
#
# The board can run two ways:
#
#   * as a desktop app — an Elixir Desktop (wx) window on the machine itself,
#     which is the default; or
#   * as a web app — headless, serving the board to a browser on a wall
#     mounted tablet. Set TASKMASTER_WEB=1. See docs/deployment.md.
#
# The SQLite path is chosen in application.ex with `put_new`, so TASKMASTER_DB
# below wins over it.

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      Base.encode64(:crypto.strong_rand_bytes(48))

  config :taskmaster, TaskmasterWeb.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: 0],
    server: true,
    secret_key_base: secret_key_base
end

if database = System.get_env("TASKMASTER_DB") do
  config :taskmaster, Taskmaster.Repo, database: database
end

# Kept last so web mode overrides the endpoint settings above.
if System.get_env("TASKMASTER_WEB") in ~w(1 true yes) do
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :taskmaster, TaskmasterWeb.Endpoint,
    # 0.0.0.0 so the tablet can reach it; a fixed port so its bookmark keeps
    # working across restarts (the desktop app uses an ephemeral one).
    http: [ip: {0, 0, 0, 0}, port: port],
    server: true,
    url: [host: System.get_env("TASKMASTER_HOST") || "localhost", port: port],
    # The tablet connects by LAN address, which will never match :url above.
    # This is a household appliance on a trusted network; do not copy this
    # setting to anything reachable from the internet.
    check_origin: false

  # The display is somebody else's browser, so no wx window here.
  config :taskmaster, desktop_window: false
end
