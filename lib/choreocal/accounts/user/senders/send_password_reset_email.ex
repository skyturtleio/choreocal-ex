defmodule Choreocal.Accounts.User.Senders.SendPasswordResetEmail do
  use AshAuthentication.Sender
  use ChoreocalWeb, :verified_routes
  import Swoosh.Email

  @impl true
  def send(user, token, _) do
    link = url(~p"/password-reset/#{token}")

    new()
    |> from({"Choreocal", Application.fetch_env!(:choreocal, :mail_from)})
    |> to(to_string(user.email))
    |> subject("Set your Choreocal password")
    |> text_body("""
    Your private teaching space is waiting.

    Set or reset your Choreocal password using this link:
    #{link}

    This link expires in 30 minutes and can only be used once.
    If you didn't request this email, you can safely ignore it.
    """)
    |> Choreocal.Mailer.deliver()
    |> case do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "Password email could not be delivered"}
    end
  end
end
