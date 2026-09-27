defmodule Choreocal.Planning.ClassSection do
  use Ash.Resource,
    otp_app: :choreocal,
    domain: Choreocal.Planning,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "class_sections"
    repo Choreocal.Repo

    references do
      reference :class, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy, update: [:name, :position]]

    create :create do
      primary? true
      accept [:class_id, :name, :position]
      change relate_actor(:owner)
      validate {Choreocal.Planning.OwnedLinks, class_id: Choreocal.Planning.Class}
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
    attribute :name, :string, public?: true, allow_nil?: false, constraints: [max_length: 100]

    attribute :position, :integer,
      public?: true,
      allow_nil?: false,
      default: 0,
      constraints: [min: 0]

    timestamps()
  end

  relationships do
    belongs_to :owner, Choreocal.Accounts.User, allow_nil?: false
    belongs_to :class, Choreocal.Planning.Class, public?: true, allow_nil?: false

    has_many :exercises, Choreocal.Planning.ClassExercise,
      destination_attribute: :section_id,
      sort: [position: :asc, id: :asc]
  end
end
