defmodule MoneyTrackWeb.IncomeSyncTest do
  use MoneyTrackWeb.ConnCase
  import MoneyTrack.Fixtures

  test "v5 preserves income; old clients cannot read or write it, including after deletion", %{
    conn: conn
  } do
    user = user()
    {category, _} = category(user)
    payload = expense(category["entityID"], 200_000) |> Map.put("kind", "income")
    {:ok, token, _} = MoneyTrack.Accounts.create_session(user, "device", "Tests")
    authenticated = put_req_header(conn, "authorization", "Bearer " <> token)
    op = operation("expense", payload)

    for version <- 1..4 do
      assert json_response(post(authenticated, "/api/v#{version}/sync", op), 426)["error"] ==
               "upgrade_required"
    end

    saved = json_response(post(authenticated, "/api/v5/sync", op), 200)["record"]
    assert saved["payload"]["kind"] == "income"
    page = json_response(get(authenticated, "/api/v5/sync"), 200)
    assert saved in page["changes"]

    for version <- 1..4 do
      assert json_response(get(authenticated, "/api/v#{version}/sync"), 426)["error"] ==
               "upgrade_required"

      assert json_response(
               post(
                 authenticated,
                 "/api/v#{version}/sync",
                 operation("expense", expense(category["entityID"]))
               ),
               426
             )["error"] == "upgrade_required"
    end

    delete =
      operation(
        "expense",
        %{"id" => payload["id"], "deletedAt" => "2026-11-05T00:00:00Z"},
        1,
        "delete"
      )

    assert json_response(post(authenticated, "/api/v5/sync", delete), 200)["record"]["deleted"]
    assert json_response(get(authenticated, "/api/v4/sync"), 426)["error"] == "upgrade_required"
  end

  test "old clients remain blocked when income is later changed into an expense", %{conn: conn} do
    user = user()
    {category, _} = category(user)
    payload = expense(category["entityID"]) |> Map.put("kind", "income")
    {:ok, _} = MoneyTrack.Ledger.apply_operation(user, operation("expense", payload))

    {:ok, _} =
      MoneyTrack.Ledger.apply_operation(
        user,
        operation("expense", Map.put(payload, "kind", "expense"), 1)
      )

    assert MoneyTrack.Ledger.has_income?(user)
    {:ok, token, _} = MoneyTrack.Accounts.create_session(user, "device", "Tests")
    authenticated = put_req_header(conn, "authorization", "Bearer " <> token)
    assert json_response(get(authenticated, "/api/v4/sync"), 426)["error"] == "upgrade_required"
    assert json_response(get(authenticated, "/api/v5/sync"), 200)["changes"] != []
  end

  test "v5 accepts unchanged legacy expense operations and converted records", %{conn: conn} do
    user = user()
    {category, _} = category(user)
    {:ok, token, _} = MoneyTrack.Accounts.create_session(user, "device", "Tests")
    authenticated = put_req_header(conn, "authorization", "Bearer " <> token)
    op = operation("expense", expense(category["entityID"]))
    saved = json_response(post(authenticated, "/api/v5/sync", op), 200)["record"]
    assert json_response(post(authenticated, "/api/v5/sync", op), 200)["record"] == saved
    refute Map.has_key?(saved["payload"], "kind")
    assert json_response(get(authenticated, "/api/v4/sync"), 200)["changes"] != []
  end
end
