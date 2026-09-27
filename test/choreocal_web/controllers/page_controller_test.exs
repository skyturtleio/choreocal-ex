defmodule ChoreocalWeb.PageControllerTest do
  use ChoreocalWeb.ConnCase

  test "anonymous planner requires sign in", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/sign-in"
  end
end
