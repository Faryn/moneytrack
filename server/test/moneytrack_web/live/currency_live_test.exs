defmodule MoneyTrackWeb.CurrencyLiveTest do
  use MoneyTrackWeb.ConnCase
  import Phoenix.LiveViewTest
  import MoneyTrack.Fixtures

  test "website converts a foreign amount and keeps its rate when editing text", %{conn: conn} do
    key = {MoneyTrack.Currency, :rates}

    :persistent_term.put(key, %{
      date: "2026-11-03",
      rates: %{"JPY" => "150"},
      fetched: System.monotonic_time(:second)
    })

    on_exit(fn -> :persistent_term.erase(key) end)
    user = user()
    {category, _} = category(user)
    {:ok, token, _} = MoneyTrack.Accounts.create_session(user, "browser", "Test browser")
    {:ok, view, _} = live(init_test_session(conn, %{session_token: token}), "/?month=2026-11")

    view
    |> form("#expense-form",
      expense: %{
        amount: "1000",
        currency: "JPY",
        description: "Sushi",
        categoryID: category["entityID"],
        day: "2026-11-04"
      }
    )
    |> render_submit()

    [expense] = MoneyTrack.Ledger.snapshot(user).expenses
    assert expense.amount == 667
    assert expense.conversion["originalAmount"] == 1000
    assert expense.conversion["rate"] == "150"
    assert has_element?(view, "#expense-#{expense.id} details", "1000 JPY")
    view |> element("#expense-#{expense.id} button", "Edit") |> render_click()

    :persistent_term.put(key, %{
      date: "2026-11-04",
      rates: %{"JPY" => "200"},
      fetched: System.monotonic_time(:second)
    })

    view |> form("#expense-form", expense: %{description: "Lunch"}) |> render_submit()
    [edited] = MoneyTrack.Ledger.snapshot(user).expenses
    assert edited.amount == 667
    assert edited.conversion == expense.conversion
    view |> element("#expense-#{expense.id} button", "Edit") |> render_click()
    view |> form("#expense-form", expense: %{amount: "2000"}) |> render_submit()
    [changed] = MoneyTrack.Ledger.snapshot(user).expenses
    assert changed.amount == 1000
    assert changed.conversion["rate"] == "200"
  end
end
