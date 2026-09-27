defmodule Choreocal.Planning do
  @moduledoc "Private, actor-scoped class planning and reusable exercise library."
  use Ash.Domain, otp_app: :choreocal

  resources do
    resource Choreocal.Planning.StarterImport do
      define :import_examples, action: :create
      define :list_imports, action: :read
    end

    resource Choreocal.Planning.Studio do
      define :list_studios, action: :read
      define :get_studio, action: :read, get_by: [:id]
      define :create_studio, action: :create
      define :update_studio, action: :update
      define :destroy_studio, action: :destroy
    end

    resource Choreocal.Planning.Exercise do
      define :list_exercises, action: :read
      define :get_exercise, action: :read, get_by: [:id]
      define :create_exercise, action: :create
      define :update_exercise, action: :update
      define :destroy_exercise, action: :destroy
    end

    resource Choreocal.Planning.Class do
      define :list_classes, action: :read
      define :get_class, action: :read, get_by: [:id]
      define :create_class, action: :create
      define :update_class, action: :update
      define :destroy_class, action: :destroy
      define :duplicate_class, action: :duplicate
      define :reorder, action: :reorder
    end

    resource Choreocal.Planning.ClassSection do
      define :create_section, action: :create
      define :update_section, action: :update
      define :destroy_section, action: :destroy
    end

    resource Choreocal.Planning.ClassExercise do
      define :create_class_exercise, action: :create
      define :update_class_exercise, action: :update
      define :destroy_class_exercise, action: :destroy
    end
  end

  def today(now \\ DateTime.utc_now()) do
    now |> DateTime.shift_zone!("America/New_York", Tzdata.TimeZoneDatabase) |> DateTime.to_date()
  end
end
