defmodule Choreocal.Planning.ClassExercise do
  use Ash.Resource,
    otp_app: :choreocal,
    domain: Choreocal.Planning,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "class_exercises"
    repo Choreocal.Repo

    references do
      reference :section, on_delete: :delete
      reference :exercise, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy, update: [:name, :cues, :position]]

    create :create do
      primary? true
      accept [:section_id, :exercise_id, :name, :cues, :position]
      change relate_actor(:owner)

      validate {Choreocal.Planning.OwnedLinks,
                section_id: Choreocal.Planning.ClassSection,
                exercise_id: Choreocal.Planning.Exercise}

      change Choreocal.Planning.Snapshot
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
    attribute :cues, :string, public?: true, constraints: [max_length: 5000]

    attribute :position, :integer,
      public?: true,
      allow_nil?: false,
      default: 0,
      constraints: [min: 0]

    timestamps()
  end

  relationships do
    belongs_to :owner, Choreocal.Accounts.User, allow_nil?: false
    belongs_to :section, Choreocal.Planning.ClassSection, public?: true, allow_nil?: false
    belongs_to :exercise, Choreocal.Planning.Exercise, public?: true
  end
end
