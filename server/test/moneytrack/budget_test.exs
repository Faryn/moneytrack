defmodule MoneyTrack.BudgetTest do
  use ExUnit.Case, async: true

  @examples Path.expand("../../../docs/contracts/budget-examples.json", __DIR__)
            |> File.read!()
            |> Jason.decode!()

  for example <- @examples["cases"] do
    @example example
    test @example["id"] do
      example = @example

      assert MoneyTrack.Budget.for_category(
               example["year"],
               example["month"],
               example["annual"],
               example["expenses"]
             ) == example["expected"]
    end
  end

  test "every cent of arbitrary annual budgets is allocated exactly once" do
    for annual <- [0, 1, 11, 12, 13, 100, 101, 600_000, 999_999] do
      allocations =
        for month <- 1..12 do
          MoneyTrack.Budget.cumulative_allocation(annual, month) -
            MoneyTrack.Budget.cumulative_allocation(annual, month - 1)
        end

      assert Enum.sum(allocations) == annual
      assert Enum.max(allocations) - Enum.min(allocations) <= 1
    end
  end
end
