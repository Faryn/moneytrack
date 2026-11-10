defmodule MoneyTrackWeb.PlanLiveTest do
  use MoneyTrackWeb.ConnCase
  import Phoenix.LiveViewTest
  import MoneyTrack.Fixtures
  alias MoneyTrack.{Accounts, Ledger}

  test "total first, category allocations, unallocated money and stale form review", %{
    conn: conn
  } do
    user = user()
    {:ok, token, _} = Accounts.create_session(user, "browser", "test")
    authed = init_test_session(conn, %{session_token: token})
    {:ok, view, _} = live(authed, "/plan?year=2026")
    refute has_element?(view, "button", "Add Category")
    view |> form("#whole-budget-form", plan: %{total: "1200"}) |> render_submit()
    assert has_element?(view, "#plan-summary", "Unallocated: €1200.00")
    view |> element("button", "Add Category") |> render_click()

    view
    |> form("#allocation-form", allocation: %{name: "Food", amount: "600"})
    |> render_submit()

    assert has_element?(view, "#plan-summary", "Unallocated: €600.00")
    plan = hd(Ledger.snapshot(user).plans)

    {:ok, _} =
      Ledger.apply_operation(user, operation("expense", expense(plan.free_category_id, 2000)))

    {:ok, budget, _} = live(authed, "/?month=2026-01")
    assert has_element?(budget, "#total-remaining", "€30.00")
    assert has_element?(budget, "#unallocated-amount", "€600.00")
    assert has_element?(budget, "#unbudgeted-spent", "−€20.00")
    payload = Ledger.envelope(plan)["payload"] |> Map.put("total", 240_000)

    assert {:ok, _} =
             Ledger.apply_operation(user, operation("budget_plan", payload, plan.revision))

    view |> form("#whole-budget-form", plan: %{total: "1800"}) |> render_submit()
    assert has_element?(view, "#plan-conflict", "€2400.00")
    assert has_element?(view, "input[name='plan[total]'][value='1800']")
    view |> element("#plan-conflict button", "Keep My Plan") |> render_click()
    assert hd(Ledger.snapshot(user).plans).total == 180_000
    food = Enum.find(Ledger.snapshot(user).categories, &(&1.name == "Food"))
    view |> element("#allocate-#{food.id} button", "Edit Allocation") |> render_click()
    view |> form("#allocation-form", allocation: %{amount: "1800"}) |> render_submit()
    assert has_element?(view, "#plan-summary", "Fully allocated")
  end
end
