defmodule Choreocal.Planning.StarterImport do
  @moduledoc "One durable receipt per owner; removing example classes does not re-enable import."
  use Ash.Resource,
    otp_app: :choreocal,
    domain: Choreocal.Planning,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "starter_imports"
    repo Choreocal.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept []
      change relate_actor(:owner)
      change Choreocal.Planning.ImportExamples
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if relating_to_actor(:owner)
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:owner)
    end
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :owner, Choreocal.Accounts.User, allow_nil?: false
  end

  identities do
    identity :one_import_per_owner, [:owner_id]
  end
end
