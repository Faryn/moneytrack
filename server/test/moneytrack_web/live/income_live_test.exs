defmodule MoneyTrackWeb.IncomeLiveTest do
  use MoneyTrackWeb.ConnCase
  import Phoenix.LiveViewTest
  import MoneyTrack.Fixtures

  test "income CRUD shows its direction and keeps budget amounts unchanged", %{conn: conn} do
    user = user()
    {category, _} = category(user, "Gehalt")

    {:ok, _} =
      MoneyTrack.Ledger.apply_operation(
        user,
        operation("year_budget", %{
          "id" => Ecto.UUID.generate(),
          "categoryID" => category["entityID"],
          "year" => 2026,
          "amount" => 120_000
        })
      )

    {:ok, token, _} = MoneyTrack.Accounts.create_session(user, "browser", "Tests")
    {:ok, view, _} = live(init_test_session(conn, %{session_token: token}), "/?month=2026-11")
    before_budget = view |> element("#total-remaining") |> render()

    view
    |> form("#expense-form",
      expense: %{
        kind: "income",
        amount: "2000,00",
        currency: "EUR",
        description: "Salary",
        categoryID: category["entityID"],
        day: "2026-11-04"
      }
    )
    |> render_submit()

    [income] = MoneyTrack.Ledger.snapshot(user).expenses
    assert income.kind == "income"
    assert income.amount == 200_000
    assert has_element?(view, "#expense-#{income.id}", "+€2000.00")
    refute has_element?(view, "#expense-#{income.id} a", "Sharing")
    assert view |> element("#total-remaining") |> render() == before_budget
    view |> element("#expense-#{income.id} button", "Edit") |> render_click()
    view |> form("#expense-form", expense: %{description: "Edited salary"}) |> render_submit()
    [edited] = MoneyTrack.Ledger.snapshot(user).expenses
    assert edited.kind == "income"
    assert edited.description == "Edited salary"
    view |> element("#expense-#{income.id} button", "Delete") |> render_click()
    assert MoneyTrack.Ledger.snapshot(user).expenses == []
    assert view |> element("#total-remaining") |> render() == before_budget
  end
end
