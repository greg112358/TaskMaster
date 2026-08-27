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
    {:ok, conn: Phoenix.ConnTest.build_conn()}
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
    Process.unlink(view.pid)

    ExUnit.Callbacks.on_exit(fn ->
      if Process.alive?(view.pid) do
        # Synchronous: returns only once the view has actually terminated.
        try do
          GenServer.stop(view.pid, :shutdown, 5000)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    view
  end
end
