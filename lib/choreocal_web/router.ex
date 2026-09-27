defmodule ChoreocalWeb.Router do
  use ChoreocalWeb, :router
  use AshAuthentication.Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ChoreocalWeb.Layouts, :root}
    plug :protect_from_forgery
    plug Choreocal.AuthRateLimit

    plug :put_secure_browser_headers, %{
      "referrer-policy" => "no-referrer",
      "cache-control" => "no-store"
    }

    plug :load_from_session
  end

  scope "/", ChoreocalWeb do
    get "/health", HealthController, :show
  end

  scope "/", ChoreocalWeb do
    pipe_through :browser
    get "/sign-in", AuthController, :sign_in
    post "/sign-in", AuthController, :authenticate
    delete "/sign-out", AuthController, :sign_out
    get "/reset", AuthController, :request_reset
    post "/reset", AuthController, :send_reset
    get "/password-reset/:token", AuthController, :reset
    post "/password-reset", AuthController, :update_password

    ash_authentication_live_session :authenticated_routes,
      on_mount: [{ChoreocalWeb.LiveUserAuth, :live_user_required}] do
      live "/", CalendarLive
    end
  end
end
