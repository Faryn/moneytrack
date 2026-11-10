defmodule MoneyTrackWeb.CurrencySyncTest do
  use MoneyTrackWeb.ConnCase
  import MoneyTrack.Fixtures

  test "v4 preserves provenance and old clients are blocked after a conversion", %{conn: conn} do
    user = user()
    {category, _} = category(user)

    conversion = %{
      "originalAmount" => 1000,
      "originalCurrency" => "JPY",
      "rate" => "150",
      "rateDate" => "2026-11-03",
      "source" => "ECB"
    }

    payload = expense(category["entityID"], 667) |> Map.put("conversion", conversion)
    {:ok, token, _} = MoneyTrack.Accounts.create_session(user, "device", "Tests")
    authenticated = put_req_header(conn, "authorization", "Bearer " <> token)
    old = post(authenticated, "/api/v3/sync", operation("expense", payload))
    assert json_response(old, 426)["error"] == "upgrade_required"
    saved = post(authenticated, "/api/v4/sync", operation("expense", payload))
    assert json_response(saved, 200)["record"]["payload"]["conversion"] == conversion
    assert json_response(get(authenticated, "/api/v3/sync"), 426)["error"] == "upgrade_required"
    page = json_response(get(authenticated, "/api/v4/sync"), 200)
    assert Enum.any?(page["changes"], &(&1["payload"]["conversion"] == conversion))
  end
end
