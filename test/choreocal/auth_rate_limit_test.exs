defmodule Choreocal.AuthRateLimitTest do
  use ExUnit.Case, async: true

  test "window boundary and independent limits are deterministic and state is bounded" do
    pid = start_supervised!({Choreocal.AuthRateLimit, name: :isolated_auth_limiter})
    for _ <- 1..3, do: assert(GenServer.call(pid, {:take, "/reset", 1_000}) == :ok)
    assert GenServer.call(pid, {:take, "/reset", 60_999}) == :limited
    assert GenServer.call(pid, {:take, "/reset", 61_000}) == :ok
    for _ <- 1..15, do: assert(GenServer.call(pid, {:take, "/sign-in", 61_000}) == :ok)
    assert GenServer.call(pid, {:take, "/sign-in", 61_001}) == :limited
    assert map_size(:sys.get_state(pid)) == 2
  end
end
