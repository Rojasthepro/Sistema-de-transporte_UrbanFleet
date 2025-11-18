defmodule UrbanFleetWebWeb.Router do
  use UrbanFleetWebWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {UrbanFleetWebWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", UrbanFleetWebWeb do
    pipe_through :browser

    live_session :public, on_mount: [{UrbanFleetWebWeb.UserAuth, :mount_current_user}] do
      live "/", LoginLive, :index
      live "/login", LoginLive, :index
      live "/ranking", RankingLive, :index
    end

    live_session :authenticated, on_mount: [{UrbanFleetWebWeb.UserAuth, :mount_current_user}] do
      live "/conductor", ConductorLive, :index
      live "/cliente", ClienteLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", UrbanFleetWebWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:urban_fleet_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev", UrbanFleetWebWeb do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: UrbanFleetWebWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
      live "/conductor", ConductorLive, :index
    end
  end
end
