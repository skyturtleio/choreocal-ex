defmodule Choreocal.Planning.Exercise do
  use Ash.Resource,
    otp_app: :choreocal,
    domain: Choreocal.Planning,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "exercises"
    repo Choreocal.Repo
  end

  actions do
    defaults [:read, :destroy, update: [:name, :category, :cues]]

    create :create do
      primary? true
      accept [:name, :category, :cues]
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
    attribute :name, :string, public?: true, allow_nil?: false, constraints: [max_length: 200]
    attribute :category, :string, public?: true, allow_nil?: false, constraints: [max_length: 100]
    attribute :cues, :string, public?: true, constraints: [max_length: 5000]
    timestamps()
  end

  relationships do
    belongs_to :owner, Choreocal.Accounts.User, allow_nil?: false
    has_many :uses, Choreocal.Planning.ClassExercise
  end
end
