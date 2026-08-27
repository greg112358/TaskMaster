defmodule TaskmasterWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use TaskmasterWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint TaskmasterWeb.Endpoint

      use TaskmasterWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import TaskmasterWeb.ConnCase
    end
  end

  setup tags do
    Taskmaster.DataCase.setup_sandbox(tags)
    {:ok, conn: authenticated_conn()}
  end

  @doc """
  A conn carrying the fixture credentials. Every page is behind
  `TaskmasterWeb.Plugs.Auth`, so this is the default; tests that are *about*
  authentication build their own conn with `Phoenix.ConnTest.build_conn/0`.
  """
  def authenticated_conn do
    Phoenix.ConnTest.build_conn()
    |> Plug.Conn.put_req_header(
      "authorization",
      Plug.BasicAuth.encode_basic_auth("test", "secret")
    )
  end

  @doc """
  Orders a mounted LiveView's shutdown with respect to the SQL sandbox.

  `live/2` links the view to the test process, so the view dies at the very
  moment the test ends — and a message still in its mailbox can then run a write
  while the *next* test has already taken over the connection. SQLite allows one
  writer, so that surfaces as an intermittent "Database busy" in an unrelated
  test.

  Unlinking and stopping the view explicitly makes the ordering deterministic:
  this `on_exit` is registered after the sandbox's, so LIFO runs it first and
  the view is gone before the owner is released.

      {:ok, view, _html} = live(conn, "/")
      view = isolate_view(view)
  """
  def isolate_view(view) do
    # Both the view and LiveViewTest's client proxy are linked to the test
    # process; unlinking only the view still lets the proxy propagate an exit.
    {_ref, _topic, proxy_pid} = view.proxy

    Process.unlink(view.pid)
    Process.unlink(proxy_pid)

    ExUnit.Callbacks.on_exit(fn ->
      # Synchronous: each returns only once that process has terminated, so no
      # write can still be in flight when the sandbox owner is released.
      for pid <- [view.pid, proxy_pid], Process.alive?(pid) do
        try do
          GenServer.stop(pid, :shutdown, 5000)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    view
  end
end
