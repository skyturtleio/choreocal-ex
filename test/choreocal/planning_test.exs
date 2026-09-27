defmodule Choreocal.PlanningTest do
  use ExUnit.Case, async: true

  test "today uses Chicago's calendar day, including daylight saving offsets" do
    assert Choreocal.Planning.today(~U[2026-07-15 04:59:59Z]) == ~D[2026-07-14]
    assert Choreocal.Planning.today(~U[2026-07-15 05:00:00Z]) == ~D[2026-07-15]
    assert Choreocal.Planning.today(~U[2026-01-15 05:59:59Z]) == ~D[2026-01-14]
    assert Choreocal.Planning.today(~U[2026-01-15 06:00:00Z]) == ~D[2026-01-15]
  end
end
