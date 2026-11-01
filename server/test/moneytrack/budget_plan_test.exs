defmodule MoneyTrack.BudgetPlanTest do
  use MoneyTrack.DataCase
  import MoneyTrack.Fixtures
  alias MoneyTrack.{Ledger, Budget}

  @examples Path.expand("../../../docs/contracts/annual-plan-examples.json", __DIR__)
            |> File.read!()
            |> Jason.decode!()
  for example <- @examples["cases"] do
    @example example
    test "annual plan: #{@example["id"]}" do
      e = @example

      assert Budget.for_plan(
               e["year"],
               e["month"],
               e["total"],
               e["allocations"],
               e["freeCategoryID"],
               e["expenses"]
             ) == e["expected"]

      monthly = Budget.joint_allocations(e["total"], e["allocations"], e["freeCategoryID"])

      for m <- 0..11 do
        assert Enum.sum(Enum.map(monthly, fn {_, cells} -> Enum.at(cells, m) end)) ==
                 Budget.cumulative_allocation(e["total"], m + 1) -
                   Budget.cumulative_allocation(e["total"], m)
      end

      for a <- e["allocations"], do: assert(Enum.sum(monthly[a["categoryID"]]) == a["amount"])
    end
  end

  test "whole plan is private, atomic, bounded, retry safe and revision checked" do
    a = user()
    b = user()
    {free, _} = category(a, "Uncategorized")
    {food, _} = category(a, "Food")
    {other, _} = category(b, "Other")

    payload = %{
      "id" => Ecto.UUID.generate(),
      "year" => 2026,
      "total" => 120_000,
      "freeCategoryID" => free["entityID"],
      "allocations" => [%{"categoryID" => food["entityID"], "amount" => 60000}]
    }

    op = operation("budget_plan", payload)
    assert {:ok, plan} = Ledger.apply_operation(a, op)
    assert {:ok, ^plan} = Ledger.apply_operation(a, op)
    assert Repo.aggregate(MoneyTrack.Ledger.BudgetPlan, :count) == 1
    assert {:error, :not_found} = Ledger.apply_operation(b, operation("budget_plan", payload, 1))

    assert {:error, {:validation, _}} =
             Ledger.apply_operation(
               a,
               operation("budget_plan", Map.put(payload, "total", 50000), 1)
             )

    assert Repo.get!(MoneyTrack.Ledger.BudgetPlan, payload["id"]).total == 120_000

    assert {:ok, new} =
             Ledger.apply_operation(
               a,
               operation("budget_plan", Map.put(payload, "total", 240_000), 1)
             )

    assert {:error, {:conflict, current}} =
             Ledger.apply_operation(a, operation("budget_plan", payload, 1))

    assert current["revision"] == new["revision"]

    bad =
      payload
      |> Map.put("id", Ecto.UUID.generate())
      |> Map.put("year", 2027)
      |> Map.put("allocations", [%{"categoryID" => other["entityID"], "amount" => 1}])

    assert {:error, :not_found} = Ledger.apply_operation(a, operation("budget_plan", bad))
    assert {:ok, feed} = Ledger.changes(b)
    refute Enum.any?(feed.changes, &(&1["entity"] == "budget_plan"))

    old =
      operation("year_budget", %{
        "id" => Ecto.UUID.generate(),
        "year" => 2026,
        "categoryID" => food["entityID"],
        "amount" => 80000
      })

    assert {:error, {:validation, _}} = Ledger.apply_operation(a, old)
    duplicate = Map.put(payload, "id", Ecto.UUID.generate())

    assert {:error, {:conflict, ^new}} =
             Ledger.apply_operation(a, operation("budget_plan", duplicate))
  end
end
