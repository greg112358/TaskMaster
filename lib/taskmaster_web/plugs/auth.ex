defmodule TaskmasterWeb.Plugs.Auth do
  @moduledoc """
  Gates every page behind the username and password in `credentials.txt`.

  Entry is HTTP basic auth, so the browser puts up its own prompt. Browsers only
  keep basic-auth credentials for the life of the session, though, and a wall
  board should be asked once and never again — so a successful login also sets a
  signed cookie holding `Taskmaster.Auth.fingerprint/0`, and that cookie is what
  lets the board back in from then on. Editing `credentials.txt` changes the
  fingerprint and locks every remembered browser back out.

  With no credentials file at all, nothing is served: the setup page is
  rendered in place of whatever was asked for, and the request is halted.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller

  alias Taskmaster.Auth

  @cookie "_taskmaster_auth"

  # "Indefinitely", as far as a family board is concerned.
  @max_age 10 * 365 * 24 * 60 * 60

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case Auth.fingerprint() do
      {:ok, fingerprint} -> authenticate(conn, fingerprint)
      :error -> setup_required(conn)
    end
  end

  defp authenticate(conn, fingerprint) do
    conn = fetch_cookies(conn, signed: [@cookie])

    cond do
      conn.cookies[@cookie] == fingerprint ->
        allow(conn, fingerprint)

      basic_auth_valid?(conn) ->
        conn |> remember(fingerprint) |> allow(fingerprint)

      true ->
        conn |> Plug.BasicAuth.request_basic_auth(realm: "Taskmaster") |> halt()
    end
  end

  # The LiveView socket cannot see the basic-auth header, so the session is what
  # carries authorisation across to it.
  defp allow(conn, fingerprint), do: put_session(conn, :auth, fingerprint)

  defp basic_auth_valid?(conn) do
    case Plug.BasicAuth.parse_basic_auth(conn) do
      {username, password} -> Auth.verify(username, password)
      :error -> false
    end
  end

  defp remember(conn, fingerprint) do
    put_resp_cookie(conn, @cookie, fingerprint,
      sign: true,
      max_age: @max_age,
      http_only: true,
      same_site: "Lax"
    )
  end

  defp setup_required(conn) do
    conn
    |> put_status(:service_unavailable)
    |> put_layout(false)
    |> put_view(html: TaskmasterWeb.AuthHTML)
    |> render(:setup_required)
    |> halt()
  end
end
