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

  scope "/", TaskmasterWeb do
    pipe_through :browser

    live "/", AppLive
  end
end
