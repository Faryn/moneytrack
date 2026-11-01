defmodule MoneyTrackWeb.Router do
  use MoneyTrackWeb, :router
  import MoneyTrackWeb.Auth, only: [fetch_browser: 2, require_browser: 2, require_api: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MoneyTrackWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :no_store
    plug :fetch_browser
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :no_store
  end

  scope "/", MoneyTrackWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  scope "/api", MoneyTrackWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  pipeline :authenticated_browser do
    plug :require_browser
  end

  pipeline :authenticated_api do
    plug :require_api
  end

  scope "/", MoneyTrackWeb do
    pipe_through [:browser, :authenticated_browser]

    live_session :authenticated, on_mount: [{MoneyTrackWeb.Auth, :required}] do
      live "/", BudgetLive, :index
      live "/account/email", EmailLive, :index
      live "/shared", SharedLive, :index
    end
  end

  scope "/api/v1", MoneyTrackWeb do
    pipe_through :api
    post "/sessions", SessionController, :api_create
  end

  scope "/api/v1", MoneyTrackWeb do
    pipe_through [:api, :authenticated_api]
    get "/account/email", EmailController, :show
    post "/account/email", EmailController, :create
    post "/account/email/verify", EmailController, :verify
    get "/session", SessionController, :api_show
    delete "/session", SessionController, :api_delete
    post "/sync", SessionController, :sync_push
    get "/sync", SessionController, :sync_pull
  end

  scope "/api/v2", MoneyTrackWeb do
    pipe_through [:api, :authenticated_api]
    post "/sync", SessionController, :sync_push
    get "/sync", SessionController, :sync_pull
  end

  defp no_store(conn, _opts), do: put_resp_header(conn, "cache-control", "no-store")

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:moneytrack, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MoneyTrackWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
