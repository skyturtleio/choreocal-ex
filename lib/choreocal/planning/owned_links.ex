defmodule Choreocal.Planning.OwnedLinks do
  @moduledoc "Validate supplied foreign keys through actor-authorized reads, not just FK existence."
  use Ash.Resource.Validation

  def validate(changeset, opts, context) do
    Enum.reduce_while(opts, :ok, fn {field, resource}, :ok ->
      case Ash.Changeset.get_attribute(changeset, field) do
        nil ->
          {:cont, :ok}

        id ->
          case Ash.get(resource, id, actor: context.actor) do
            {:ok, %{id: ^id}} -> {:cont, :ok}
            _ -> {:halt, {:error, field: field, message: "is not available in your workspace"}}
          end
      end
    end)
  end
end
