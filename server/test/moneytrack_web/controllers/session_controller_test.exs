defmodule MoneyTrackWeb.SessionControllerTest do
  use MoneyTrackWeb.ConnCase
  import MoneyTrack.Fixtures

  test "native login, authentication boundary and revocation", %{conn: conn} do
    user = user()
    assert json_response(get(conn, "/api/v1/sync"), 401)["error"] == "unauthorized"

    response =
      post(conn, "/api/v1/sessions", %{username: user.username, password: password()})
      |> json_response(200)

    refute Map.has_key?(response["user"], "hashed_password")
    authorized = put_req_header(recycle(conn), "authorization", "Bearer " <> response["token"])
    assert json_response(get(authorized, "/api/v1/sync"), 200)["changes"] == []
    assert response(delete(authorized, "/api/v1/session"), 204) == ""
    assert json_response(get(authorized, "/api/v1/sync"), 401)["error"] == "unauthorized"
  end

  test "incorrect and missing usernames return the same failure", %{conn: conn} do
    user = user()

    one =
      post(conn, "/api/v1/sessions", %{username: user.username, password: "incorrect"})
      |> json_response(401)

    two =
      post(recycle(conn), "/api/v1/sessions", %{username: "missing-user", password: "incorrect"})
      |> json_response(401)

    assert one == two
  end

  test "login is throttled", %{conn: conn} do
    username = "limited#{System.unique_integer([:positive])}"

    for _ <- 1..10 do
      assert conn
             |> recycle()
             |> post("/api/v1/sessions", %{username: username, password: "incorrect"})
             |> json_response(401)
    end

    limited =
      post(recycle(conn), "/api/v1/sessions", %{username: username, password: "incorrect"})

    assert json_response(limited, 429)["error"] == "rate_limited"
    assert get_resp_header(limited, "retry-after") != []
  end

  test "browser login renews its session, cannot act as a bearer credential, and logs out", %{
    conn: conn
  } do
    user = user()
    conn = get(conn, "/login")
    assert html_response(conn, 200) =~ "login-form"
    conn = conn |> recycle() |> post("/login", %{username: user.username, password: password()})
    assert redirected_to(conn) == "/"
    browser_token = get_session(conn, :session_token)
    assert is_binary(browser_token)

    denied =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> browser_token)
      |> get("/api/v1/sync")

    assert json_response(denied, 401)
    assert redirected_to(conn |> recycle() |> delete("/logout")) == "/login"
  end
end
