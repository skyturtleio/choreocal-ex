defmodule ChoreocalWeb.AuthController do
  use ChoreocalWeb, :controller
  use AshAuthentication.Phoenix.Controller

  def sign_in(conn, _), do: page(conn, :sign_in)
  def request_reset(conn, _), do: page(conn, :request_reset)
  def reset(conn, %{"token" => token}), do: page(conn, :reset, %{"reset_token" => token})

  def authenticate(conn, %{"user" => params}) do
    case auth(:sign_in, params) do
      {:ok, user} ->
        success(conn, :sign_in, user, nil)

      _ ->
        conn
        |> put_status(:unprocessable_entity)
        |> page(:sign_in, %{}, "Email or password was incorrect.")
    end
  end

  def send_reset(conn, %{"user" => params}) do
    auth(:reset_request, Map.take(params, ["email"]))

    conn
    |> put_flash(
      :info,
      "If that email belongs to your account, password instructions are on their way."
    )
    |> redirect(to: ~p"/reset")
  end

  def update_password(conn, %{"user" => params}) do
    case auth(:reset, params) do
      {:ok, user} ->
        ChoreocalWeb.LiveUserAuth.disconnect(user)

        conn
        |> clear_session(:choreocal)
        |> put_flash(:info, "Your password is set. Sign in to your teaching space.")
        |> redirect(to: ~p"/sign-in")

      _ ->
        conn
        |> put_status(:unprocessable_entity)
        |> page(
          :reset,
          Map.take(params, ["reset_token"]),
          "Use matching passwords of 12–72 characters. If your link expired or was used, request a new one."
        )
    end
  end

  def success(conn, _activity, user, _token) do
    conn |> configure_session(renew: true) |> store_in_session(user) |> redirect(to: ~p"/")
  end

  def failure(conn, _activity, _reason), do: redirect(conn, to: ~p"/sign-in")

  def sign_out(conn, _) do
    signed_out = clear_session(conn, :choreocal)

    if conn.assigns[:current_user],
      do: ChoreocalWeb.LiveUserAuth.disconnect(conn.assigns.current_user)

    signed_out
    |> configure_session(renew: true)
    |> redirect(to: ~p"/sign-in")
  end

  defp auth(action, params) do
    Choreocal.Accounts.User
    |> AshAuthentication.Info.strategy!(:password)
    |> AshAuthentication.Strategy.action(action, params)
  end

  defp page(conn, mode, params \\ %{}, error \\ nil) do
    conn
    |> render(:page,
      mode: mode,
      form: Phoenix.Component.to_form(params, as: :user),
      error: error,
      page_title: if(mode == :sign_in, do: "Welcome back", else: "Password help")
    )
  end
end
