defmodule TaskmasterWeb.AuthTest do
  use TaskmasterWeb.ConnCase

  alias Taskmaster.Auth

  defp anonymous, do: Phoenix.ConnTest.build_conn()

  defp with_basic_auth(conn, user, pass) do
    put_req_header(conn, "authorization", Plug.BasicAuth.encode_basic_auth(user, pass))
  end

  describe "without credentials" do
    setup do
      Application.put_env(:taskmaster, :credentials_path, "/nonexistent/credentials.txt")

      on_exit(fn ->
        Application.put_env(
          :taskmaster,
          :credentials_path,
          Path.expand("../support/credentials.txt", __DIR__)
        )
      end)
    end

    test "every page is replaced by the setup page", %{conn: conn} do
      conn = get(conn, "/")

      assert conn.status == 503
      assert html_response(conn, 503) =~ "Add credentials to credentials.txt"
      # Even a valid-looking login gets nowhere.
      refute html_response(conn, 503) =~ "Groceries"
    end

    test "the board itself is never rendered" do
      conn = get(anonymous(), "/")

      refute html_response(conn, 503) =~ "phx-hook"
    end
  end

  describe "with credentials" do
    test "an anonymous request is challenged" do
      conn = get(anonymous(), "/")

      assert conn.status == 401
      assert [~s(Basic realm="Taskmaster")] = get_resp_header(conn, "www-authenticate")
    end

    test "a wrong password is challenged" do
      conn = anonymous() |> with_basic_auth("test", "wrong") |> get("/")

      assert conn.status == 401
    end

    test "a wrong username is challenged" do
      conn = anonymous() |> with_basic_auth("nobody", "secret") |> get("/")

      assert conn.status == 401
    end

    test "the right pair gets the board" do
      conn = anonymous() |> with_basic_auth("test", "secret") |> get("/")

      assert html_response(conn, 200) =~ "Groceries"
    end
  end

  describe "staying logged in" do
    test "a successful login sets a long-lived signed cookie" do
      conn = anonymous() |> with_basic_auth("test", "secret") |> get("/")

      cookie = conn.resp_cookies["_taskmaster_auth"]

      assert cookie.max_age > 60 * 60 * 24 * 365
      assert cookie.http_only
      # Signed, so the browser never sees the fingerprint itself.
      {:ok, fingerprint} = Auth.fingerprint()
      refute cookie.value == fingerprint
    end

    test "the cookie alone gets back in, with no password" do
      logged_in = anonymous() |> with_basic_auth("test", "secret") |> get("/")

      # Two cookies come back (the session and the auth one); replay both.
      cookie =
        logged_in
        |> Plug.Conn.get_resp_header("set-cookie")
        |> Enum.map_join("; ", &(&1 |> String.split(";") |> hd()))

      conn =
        Phoenix.ConnTest.build_conn()
        |> put_req_header("cookie", cookie)
        |> get("/")

      assert html_response(conn, 200) =~ "Groceries"
    end

    test "a forged cookie does not" do
      conn =
        anonymous()
        |> put_req_cookie("_taskmaster_auth", "made-up")
        |> get("/")

      assert conn.status == 401
    end
  end

  describe "the credentials file" do
    test "splits on the first colon only, so passwords may contain one" do
      assert {:ok, %{username: "test", password: "secret"}} = Auth.credentials()
    end

    test "reports itself configured" do
      assert Auth.configured?()
    end
  end
end
