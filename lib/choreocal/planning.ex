defmodule Choreocal.Planning do
  @moduledoc "Planning domain. Persisted class and exercise resources follow the authentication foundation."
  use Ash.Domain, otp_app: :choreocal

  def today(now \\ DateTime.utc_now()) do
    now |> DateTime.shift_zone!("America/Chicago", Tzdata.TimeZoneDatabase) |> DateTime.to_date()
  end
end
