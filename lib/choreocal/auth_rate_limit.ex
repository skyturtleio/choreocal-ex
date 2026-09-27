defmodule Choreocal.AuthRateLimit do
  @moduledoc "Bounded, node-local admission control for this single-owner application."
  use GenServer
  import Plug.Conn
  @limits %{"/sign-in" => 15, "/reset" => 3, "/password-reset" => 10}
  @window 60_000

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, %{}, name: Keyword.get(opts, :name, __MODULE__))

  def init(state) when is_map(state), do: {:ok, state}
  def init(opts) when is_list(opts), do: opts

  def call(%{method: "POST", request_path: path} = conn, _) when is_map_key(@limits, path) do
    case GenServer.call(__MODULE__, {:take, path, System.monotonic_time(:millisecond)}) do
      :ok ->
        conn

      :limited ->
        conn
        |> put_resp_header("retry-after", "60")
        |> send_resp(429, "Please wait a minute before trying again.")
        |> halt()
    end
  end

  def call(conn, _), do: conn

  # Only three statically defined buckets exist. Client input cannot grow state,
  # evade limits through forwarded headers, or trigger unbounded email/bcrypt work.
  def handle_call({:take, path, now}, _, state) when is_map_key(@limits, path) do
    {count, deadline} = Map.get(state, path, {0, now + @window})
    {count, deadline} = if now >= deadline, do: {0, now + @window}, else: {count, deadline}

    if count < Map.fetch!(@limits, path) do
      {:reply, :ok, Map.put(state, path, {count + 1, deadline})}
    else
      {:reply, :limited, state}
    end
  end
end
