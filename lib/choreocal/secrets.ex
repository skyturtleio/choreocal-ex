defmodule Choreocal.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Choreocal.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:choreocal, :token_signing_secret)
  end
end
