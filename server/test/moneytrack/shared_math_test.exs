defmodule MoneyTrack.SharedMathTest do
  use ExUnit.Case, async: true

  @examples Path.expand("../../../docs/contracts/shared-expense-examples.json", __DIR__)
            |> File.read!()
            |> Jason.decode!()
  for example <- @examples["cases"] do
    @example example
    test @example["id"] do
      e = @example

      assert MoneyTrack.SharedMath.calculate(e["amount"], e["split"], e["paidByUser"]) ==
               e["expected"]
    end
  end

  test "both views preserve every cent and opposite debts" do
    for amount <- [1, 2, 3, 99, 100, 101, 99_999_999_999],
        split <- ["all", "half", "none"],
        payer <- [true, false] do
      inverse =
        case split do
          "all" -> "none"
          "none" -> "all"
          "half" -> "half"
        end

      own = MoneyTrack.SharedMath.calculate(amount, split, payer)
      other = MoneyTrack.SharedMath.calculate(amount, inverse, !payer)
      assert own["personalShare"] + other["personalShare"] == amount
      assert own["balance"] == -other["balance"]
    end
  end

  test "invalid monetary amounts cannot produce a split" do
    for amount <- [0, -1, 100_000_000_000, 10.5] do
      assert_raise FunctionClauseError, fn ->
        MoneyTrack.SharedMath.calculate(amount, "half", true)
      end
    end
  end
end
