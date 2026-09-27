defmodule Choreocal.Planning.Timezone do
  use Ash.Resource.Validation

  def validate(changeset, _, _) do
    if Ash.Changeset.get_attribute(changeset, :timezone) in Tzdata.zone_list(),
      do: :ok,
      else: {:error, field: :timezone, message: "must be an IANA timezone"}
  end
end
