defmodule Choreocal.Planning.Studio do
  use Ash.Resource,
    otp_app: :choreocal,
    domain: Choreocal.Planning,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "studios"
    repo Choreocal.Repo
  end

  actions do
    defaults [:read, :destroy, update: [:name, :address]]

    create :create do
      primary? true
      accept [:name, :address]
      change relate_actor(:owner)
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if relating_to_actor(:owner)
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if relates_to_actor_via(:owner)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true, allow_nil?: false, constraints: [max_length: 120]
    attribute :address, :string, public?: true, constraints: [max_length: 1000]
    timestamps()
  end

  relationships do
    belongs_to :owner, Choreocal.Accounts.User, allow_nil?: false
  end
end
