defmodule NostrSpamFighterWeb.Router do
  use NostrSpamFighterWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {NostrSpamFighterWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug NostrSpamFighterWeb.Plugs.ApiAuth
  end

  pipeline :auth_api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
  end

  scope "/", NostrSpamFighterWeb do
    get "/health", HealthController, :show
    get "/health/ready", HealthController, :ready
  end

  scope "/", NostrSpamFighterWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/login", AuthController, :login
    delete "/logout", AuthController, :delete
  end

  scope "/", NostrSpamFighterWeb do
    pipe_through :auth_api
    post "/auth/nostr", AuthController, :create
  end

  live_session :admin, on_mount: [NostrSpamFighterWeb.Hooks.RequireAdmin] do
    scope "/", NostrSpamFighterWeb do
      pipe_through :browser

      live "/dashboard", DashboardLive
      live "/events", EventLive.Index
      live "/events/:id", EventLive.Show
      live "/categories", CategoryLive.Index
      live "/categories/:id", CategoryLive.Show
      live "/blocklists", BlocklistLive.Index
      live "/blocklists/:id", BlocklistLive.Show
      live "/matches", MatchLive.Index
      live "/relays", RelayLive.Index
      live "/admins", AdminLive.Index
      live "/api-keys", ApiKeyLive.Index
      live "/settings", SettingsLive
    end
  end

  scope "/api/v1", NostrSpamFighterWeb do
    pipe_through :api

    get "/articles/:naddr/moderation", ArticleModerationController, :show
    post "/articles/moderation/check", ArticleModerationController, :check
  end

  if Application.compile_env(:nostr_spam_fighter, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: NostrSpamFighterWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
