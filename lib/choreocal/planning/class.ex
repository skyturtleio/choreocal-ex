defmodule Choreocal.Planning.Class do
  use Ash.Resource,
    otp_app: :choreocal,
    domain: Choreocal.Planning,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "classes"
    repo Choreocal.Repo

    references do
      reference :studio, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :starts_at, :ends_at, :timezone, :studio_id, :playlist_name, :playlist_url]
      change relate_actor(:owner)
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:name, :starts_at, :ends_at, :timezone, :studio_id, :playlist_name, :playlist_url]
    end

    create :duplicate do
      accept [:starts_at, :ends_at, :timezone]
      argument :source_id, :uuid, allow_nil?: false
      change relate_actor(:owner)
      change Choreocal.Planning.Duplicate
    end

    action :reorder, :boolean do
      argument :class_id, :uuid, allow_nil?: false
      argument :section_id, :uuid
      argument :ids, {:array, :uuid}, allow_nil?: false
      run Choreocal.Planning.Reorder
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if relating_to_actor(:owner)
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if relates_to_actor_via(:owner)
    end

    policy action(:reorder) do
      authorize_if actor_present()
    end
  end

  validations do
    validate {Choreocal.Planning.OwnedLinks, studio_id: Choreocal.Planning.Studio}
    validate compare(:ends_at, greater_than: :starts_at)
    validate Choreocal.Planning.Timezone
    validate match(:playlist_url, ~r{\Ahttps://open\.spotify\.com/[^\s]+\z})
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true, allow_nil?: false, constraints: [max_length: 200]
    attribute :starts_at, :utc_datetime, public?: true, allow_nil?: false
    attribute :ends_at, :utc_datetime, public?: true, allow_nil?: false
    attribute :timezone, :string, public?: true, allow_nil?: false, default: "America/New_York"
    attribute :playlist_name, :string, public?: true, constraints: [max_length: 200]
    attribute :playlist_url, :string, public?: true, constraints: [max_length: 1000]
    timestamps()
  end

  relationships do
    belongs_to :owner, Choreocal.Accounts.User, allow_nil?: false
    belongs_to :studio, Choreocal.Planning.Studio, public?: true
    has_many :sections, Choreocal.Planning.ClassSection, sort: [position: :asc, id: :asc]
  end
end
