defmodule Choreocal.Planning.Reorder do
  use Ash.Resource.Actions.Implementation
  alias Choreocal.Planning

  def run(input, _, context) do
    Choreocal.Repo.transaction(fn ->
      class =
        case Planning.get_class(input.arguments.class_id, actor: context.actor) do
          {:ok, class} when not is_nil(class) -> class
          _ -> Choreocal.Repo.rollback("Class is unavailable")
        end

      # Serialize simultaneous reorders of the same class without trusting submitted IDs.
      Choreocal.Repo.query!("SELECT id FROM classes WHERE id = $1 FOR UPDATE", [
        Ecto.UUID.dump!(class.id)
      ])

      class = Ash.load!(class, [sections: :exercises], actor: context.actor)

      rows =
        if input.arguments[:section_id] do
          case Enum.find(class.sections, &(&1.id == input.arguments[:section_id])) do
            nil -> Choreocal.Repo.rollback("Section is unavailable")
            section -> section.exercises
          end
        else
          class.sections
        end

      ids = input.arguments.ids

      if Enum.sort(ids) != Enum.sort(Enum.map(rows, & &1.id)),
        do: Choreocal.Repo.rollback("Order must contain each current row exactly once")

      notifications =
        Enum.with_index(ids, fn id, index ->
          row = Enum.find(rows, &(&1.id == id))

          {_record, notifications} =
            row
            |> Ash.Changeset.for_update(:update, %{position: index}, actor: context.actor)
            |> Ash.update!(return_notifications?: true)

          notifications
        end)

      List.flatten(notifications)
    end)
    |> case do
      {:ok, notifications} ->
        Ash.Notifier.notify(notifications)
        {:ok, true}

      {:error, error} ->
        {:error, error}
    end
  end
end
