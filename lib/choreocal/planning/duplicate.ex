defmodule Choreocal.Planning.Duplicate do
  use Ash.Resource.Change
  alias Choreocal.Planning

  def change(changeset, _, context) do
    case Planning.get_class(Ash.Changeset.get_argument(changeset, :source_id),
           actor: context.actor,
           load: [sections: :exercises]
         ) do
      {:ok, source} when not is_nil(source) ->
        changeset
        |> Ash.Changeset.change_attributes(
          Map.take(source, [:name, :studio_id, :playlist_name, :playlist_url])
        )
        |> Ash.Changeset.after_action(fn _, copy ->
          Enum.each(source.sections, fn section ->
            new_section =
              Planning.create_section!(
                %{class_id: copy.id, name: section.name, position: section.position},
                actor: context.actor
              )

            Enum.each(section.exercises, fn exercise ->
              attrs =
                exercise
                |> Map.take([:name, :cues, :position, :exercise_id])
                |> Map.put(:section_id, new_section.id)

              Planning.create_class_exercise!(attrs, actor: context.actor)
            end)
          end)

          {:ok, copy}
        end)

      _ ->
        Ash.Changeset.add_error(changeset, field: :source_id, message: "is unavailable")
    end
  end
end
