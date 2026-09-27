defmodule Choreocal.Release do
  @moduledoc "Private release operations. Never prints passwords or authentication tokens."
  @app :choreocal

  def migrate do
    Application.load(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  def provision_owner(email) when is_binary(email) do
    # `eval` runs beside the deployed release, so never bind its HTTP port.
    endpoint = Application.fetch_env!(@app, ChoreocalWeb.Endpoint)
    Application.put_env(@app, ChoreocalWeb.Endpoint, Keyword.put(endpoint, :server, false))
    {:ok, _} = Application.ensure_all_started(@app)
    provision(email)
  end

  def provision(email) do
    # A database advisory lock serializes concurrent bootstrap calls. A second
    # recipient can never become an additional account through this task.
    result =
      Choreocal.Repo.transaction(fn ->
        Choreocal.Repo.query!("SELECT pg_advisory_xact_lock(782348923)")

        case Ash.read!(Choreocal.Accounts.User, authorize?: false) do
          [] ->
            password = :crypto.strong_rand_bytes(48) |> Base.url_encode64(padding: false)

            Choreocal.Accounts.User
            |> Ash.Changeset.for_create(:provision, %{
              email: email,
              hashed_password: Bcrypt.hash_pwd_salt(password)
            })
            |> Ash.create!(authorize?: false)

          [user] ->
            if String.downcase(to_string(user.email)) != String.downcase(email) do
              Choreocal.Repo.rollback(:owner_already_exists)
            end

            user
        end
      end)

    case result do
      {:ok, user} ->
        # Public reset requests deliberately hide delivery failures. A private
        # provisioning command must instead report whether email was accepted.
        with {:ok, token, _claims} <-
               AshAuthentication.Jwt.token_for_user(
                 user,
                 %{"act" => "reset_password_with_token"},
                 purpose: :reset_password_with_token,
                 token_lifetime: {30, :minutes}
               ) do
          Choreocal.Accounts.User.Senders.SendPasswordResetEmail.send(user, token, [])
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
