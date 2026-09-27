defmodule Choreocal.Accounts do
  use Ash.Domain,
    otp_app: :choreocal

  resources do
    resource Choreocal.Accounts.Token
    resource Choreocal.Accounts.User
  end
end
