defmodule ChoreocalWeb.HealthController do
  use ChoreocalWeb, :controller
  def show(conn, _), do: json(conn, %{status: "ok"})
end
