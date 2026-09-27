defmodule Choreocal.Accounts.User do
  use Ash.Resource,
    otp_app: :choreocal,
    domain: Choreocal.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end
    end

    tokens do
      enabled? true
      token_resource Choreocal.Accounts.Token
      signing_secret Choreocal.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
      token_lifetime {7, :days}
    end

    strategies do
      password :password do
        identity_field :email
        registration_enabled? false
        sign_in_tokens_enabled? false
        hash_provider AshAuthentication.BcryptProvider

        resettable do
          sender Choreocal.Accounts.User.Senders.SendPasswordResetEmail
          token_lifetime {30, :minutes}
          password_reset_action_name :reset_password_with_token
          request_password_reset_action_name :request_password_reset_token
        end
      end
    end
  end

  postgres do
    table "users"
    repo Choreocal.Repo
  end

  actions do
    defaults [:read]

    # This action has no authorizing policy and no HTTP route. Only the private
    # release task may call it with authorization explicitly disabled.
    create :provision do
      accept [:email, :hashed_password]
      validate match(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
    end

    read :get_by_subject do
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      get_by :email
    end

    update :reset_password_with_token do
      argument :reset_token, :string, allow_nil?: false, sensitive?: true

      argument :password, :string,
        allow_nil?: false,
        sensitive?: true,
        constraints: [min_length: 12, max_length: 72]

      argument :password_confirmation, :string, allow_nil?: false, sensitive?: true
      validate AshAuthentication.Strategy.Password.ResetTokenValidation
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation
      change AshAuthentication.Strategy.Password.HashPasswordChange
      change AshAuthentication.GenerateTokenChange
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :ci_string, allow_nil?: false, public?: true
    attribute :hashed_password, :string, allow_nil?: false, sensitive?: true
    attribute :confirmed_at, :utc_datetime_usec
  end

  identities do
    identity :unique_email, [:email]
  end
end
