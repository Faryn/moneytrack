defmodule MoneyTrackWeb.EntrySharingLiveTest do
  use MoneyTrackWeb.ConnCase
  import Phoenix.LiveViewTest
  import MoneyTrack.Fixtures

  test "entry chooses an accepted person and shares without another invitation", %{conn: conn} do
    a = user()
    b = user()
    email = "#{b.username}@example.org"

    MoneyTrack.Repo.insert!(%MoneyTrack.Accounts.VerifiedEmail{
      user_id: b.id,
      address: email,
      verified_at: DateTime.utc_now()
    })

    {category, _} = category(a)
    source = expense(category["entityID"])
    {:ok, _} = MoneyTrack.Ledger.apply_operation(a, operation("expense", source))

    {:ok, _} =
      MoneyTrack.Ledger.apply_operation(
        a,
        operation("shared_expense", %{
          "id" => source["id"],
          "command" => "share",
          "recipientEmail" => email,
          "sourceRevision" => 1,
          "paidByCreator" => true,
          "creatorSplit" => "half"
        })
      )

    {:ok, _} =
      MoneyTrack.Ledger.apply_operation(
        b,
        operation("shared_expense", %{"id" => source["id"], "command" => "accept"}, 1)
      )

    {:ok, token, _} = MoneyTrack.Accounts.create_session(a, "browser", "Test browser")
    {:ok, view, _} = live(init_test_session(conn, %{session_token: token}), "/?month=2026-01")
    assert has_element?(view, "select[name='expense[shareWith]'] option", b.username)

    view
    |> form("#expense-form",
      expense: %{
        amount: "5.01",
        description: "rewe",
        categoryID: category["entityID"],
        shareWith: b.id,
        day: "2026-01-15"
      }
    )
    |> render_submit()

    value = Enum.find(MoneyTrack.Ledger.snapshot(b).expenses, &(&1.description == "rewe"))
    assert value.personal_share == 250
    assert MoneyTrack.Repo.get!(MoneyTrack.Sharing.SharedExpense, value.id).status == "accepted"
  end
end
