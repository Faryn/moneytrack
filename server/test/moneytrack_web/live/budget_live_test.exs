defmodule MoneyTrackWeb.BudgetLiveTest do
  use MoneyTrackWeb.ConnCase

  import Phoenix.LiveViewTest

  test "budget overview mounts over LiveView without invented financial figures", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#budget-heading", "Your budget")
    assert has_element?(view, "#budget-overview", "No budget yet")
  end
end
