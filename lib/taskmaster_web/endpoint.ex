defmodule TaskmasterWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :taskmaster

  @session_options [
    store: :ets,
    key: "_taskmaster_key",
    table: :session
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :taskmaster,
    gzip: not code_reloading?,
    only: TaskmasterWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :taskmaster
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug TaskmasterWeb.Router

  # Override url/0 to resolve port: 0 to the actual bound port
  defoverridable url: 0

  def url do
    base_url = super()

    if String.contains?(base_url, ":0") do
      case server_info(:http) do
        {:ok, {_ip, port}} ->
          String.replace(base_url, ":0", ":#{port}")

        _ ->
          base_url
      end
    else
      base_url
    end
  end
end
