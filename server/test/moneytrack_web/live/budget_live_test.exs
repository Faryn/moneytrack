defmodule MoneyTrackWeb.BudgetLiveTest do
  use MoneyTrackWeb.ConnCase

  import Phoenix.LiveViewTest

  test "German remains active after a LiveView event", %{conn: conn} do
    user = MoneyTrack.Fixtures.user()
    {:ok, token, _} = MoneyTrack.Accounts.create_session(user, "browser", "Test browser")

    conn =
      conn
      |> init_test_session(%{session_token: token})
      |> put_req_header("accept-language", "de-DE")

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#budget-heading", "Dein Budget")

    view
    |> form("#expense-form", expense: %{amount: "0", day: "2026-01-15"})
    |> render_submit()

    assert render(view) =~ "Gib einen Betrag wie 78,50"
  end

  test "budget overview mounts over LiveView without invented financial figures", %{conn: conn} do
    user = MoneyTrack.Fixtures.user()
    {:ok, token, _} = MoneyTrack.Accounts.create_session(user, "browser", "Test browser")
    conn = conn |> init_test_session(%{session_token: token})
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#budget-heading", "Your budget")
    assert has_element?(view, "#budget-overview", "No budget yet")
  end

  test "website edits reach the same sync feed and preserve stale form values", %{conn: conn} do
    import MoneyTrack.Fixtures
    alias MoneyTrack.Ledger
    user = user()
    {category, _} = category(user)

    {:ok, _} =
      Ledger.apply_operation(
        user,
        operation("year_budget", %{
          "id" => Ecto.UUID.generate(),
          "categoryID" => category["entityID"],
          "year" => 2026,
          "amount" => 120_000
        })
      )

    {:ok, token, _} = MoneyTrack.Accounts.create_session(user, "browser", "Test browser")
    {:ok, view, _} = live(init_test_session(conn, %{session_token: token}), "/?month=2026-01")

    view
    |> form("#expense-form",
      expense: %{
        amount: "78,00",
        description: "Theodor",
        categoryID: category["entityID"],
        day: "2026-01-15"
      }
    )
    |> render_submit()

    assert has_element?(view, "#total-remaining", "€22.00")
    [expense] = Ledger.snapshot(user).expenses
    {:ok, page} = Ledger.changes(user)
    assert List.last(page.changes)["payload"]["amount"] == 7800
    view |> element("#expense-#{expense.id} button", "Edit") |> render_click()

    payload =
      Ledger.envelope(expense)["payload"]
      |> Map.merge(%{"amount" => 9800, "personalShare" => 9800})

    {:ok, _} = Ledger.apply_operation(user, operation("expense", payload, 1))
    view |> form("#expense-form", expense: %{amount: "88.00"}) |> render_submit()
    assert has_element?(view, "#sync-conflict", "€98.00")
    assert has_element?(view, "input[name='expense[amount]'][value='88.00']")
    view |> element("#sync-conflict button", "Keep My Changes") |> render_click()
    [updated] = Ledger.snapshot(user).expenses
    assert updated.amount == 8800
    assert updated.revision == 3
    {:ok, edits} = Ledger.changes(user, page.cursor)
    assert Enum.map(edits.changes, & &1["revision"]) == [2, 3]
    view |> element("#expense-#{expense.id} button", "Delete") |> render_click()
    assert Ledger.snapshot(user).expenses == []
    assert has_element?(view, "#total-remaining", "€100.00")
  end

  test "unauthenticated visitors cannot access the ledger", %{conn: conn} do
    assert redirected_to(get(conn, "/")) == "/login"
  end

  test "a selected calendar year initializes a fresh yearly plan", %{conn: conn} do
    user = MoneyTrack.Fixtures.user()
    {:ok, token, _} = MoneyTrack.Accounts.create_session(user, "browser", "Test browser")
    {:ok, view, _} = live(init_test_session(conn, %{session_token: token}), "/?month=2027-01")
    assert has_element?(view, "a[href='/plan?year=2027']")
  end

  test "saving a budget preserves an expense draft in the other form", %{conn: conn} do
    import MoneyTrack.Fixtures
    alias MoneyTrack.Ledger
    user = user()
    {category, _} = category(user)

    {:ok, _} =
      Ledger.apply_operation(
        user,
        operation("year_budget", %{
          "id" => Ecto.UUID.generate(),
          "categoryID" => category["entityID"],
          "year" => 2026,
          "amount" => 120_000
        })
      )

    {:ok, original} =
      Ledger.apply_operation(user, operation("expense", expense(category["entityID"])))

    {:ok, token, _} = MoneyTrack.Accounts.create_session(user, "browser", "Test browser")
    {:ok, view, _} = live(init_test_session(conn, %{session_token: token}), "/?month=2026-01")
    view |> element("#expense-#{original["entityID"]} button", "Edit") |> render_click()

    view
    |> form("#expense-form", expense: %{amount: "88.00", description: "Unsaved draft"})
    |> render_change()

    view |> element("button[phx-click='edit_budget']", "Edit yearly budget") |> render_click()
    view |> form("#budget-form", budget: %{amount: "2400"}) |> render_submit()
    assert has_element?(view, "input[name='expense[amount]'][value='88.00']")
    assert has_element?(view, "input[name='expense[id]'][value='#{original["entityID"]}']")
    assert has_element?(view, "#total-remaining", "€122.00")
    view |> form("#expense-form") |> render_submit()
    [saved] = Ledger.snapshot(user).expenses
    assert saved.amount == 8800
    assert saved.description == "Unsaved draft"
  end
end
