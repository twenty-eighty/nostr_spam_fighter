defmodule NostrSpamFighterWeb.HealthControllerTest do
  use NostrSpamFighterWeb.ConnCase

  test "health is ok", %{conn: conn} do
    conn = get(conn, "/health")
    assert json_response(conn, 200)["status"] == "ok"
  end

  test "ready checks db and cache", %{conn: conn} do
    conn = get(conn, "/health/ready")
    assert json_response(conn, 200)["status"] == "ready"
  end
end
