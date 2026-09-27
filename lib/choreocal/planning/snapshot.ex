defmodule Choreocal.Planning.Snapshot do
  use Ash.Resource.Change

  def change(changeset, _, context) do
    case Ash.Changeset.get_attribute(changeset, :exercise_id) do
      nil ->
        changeset

      id ->
        case Ash.get(Choreocal.Planning.Exercise, id, actor: context.actor) do
          {:ok, exercise} when not is_nil(exercise) ->
            # Explicit values are already snapshots (e.g. when duplicating).
            changeset
            |> Ash.Changeset.change_new_attribute(:name, exercise.name)
            |> Ash.Changeset.change_new_attribute(:cues, exercise.cues)

          _ ->
            Ash.Changeset.add_error(changeset, field: :exercise_id, message: "is unavailable")
        end
    end
  end
end
