import Config

# Runtime config for Desktop app
# SQLite database path is configured in application.ex

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      Base.encode64(:crypto.strong_rand_bytes(48))

  config :taskmaster, TaskmasterWeb.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: 0],
    server: true,
    secret_key_base: secret_key_base
end
