defmodule TaskmasterWeb.Router do
  use TaskmasterWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TaskmasterWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug TaskmasterWeb.Plugs.Auth
  end

  # The root layout reads `@theme` and defaults to light, which is what the wall
  # board wants. Only /wkuk opts into dark.
  defp put_dark_theme(conn, _opts), do: Plug.Conn.assign(conn, :theme, "dark")

  pipeline :dark do
    plug :put_dark_theme
  end

  scope "/", TaskmasterWeb do
    pipe_through :browser

    live "/", AppLive
  end

  # The sketch ranking board. A second front end on the same release and the
  # same login, deliberately separate from the wall board's single route.
  scope "/wkuk", TaskmasterWeb do
    pipe_through [:browser, :dark]

    live "/", WkukLive
    live "/:user", WkukBoardLive
  end
end
