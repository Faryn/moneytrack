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

  @settlements Path.expand("../../../docs/contracts/settlement-examples.json", __DIR__)
               |> File.read!()
               |> Jason.decode!()
  for example <- @settlements["cases"] do
    @settlement example
    test "repayment: #{@settlement["id"]}" do
      e = @settlement

      expenses =
        Enum.map(
          e["expenses"],
          &MoneyTrack.SharedMath.calculate(&1["amount"], &1["split"], &1["paidByUser"])
        )

      result = MoneyTrack.SharedMath.summarize(expenses, e["repayments"])
      assert result == e["expected"]
      before = MoneyTrack.SharedMath.summarize(expenses, [])
      assert result["personalSpending"] == before["personalSpending"]
      assert result["otherSpending"] == before["otherSpending"]

      peer_expenses =
        Enum.map(
          expenses,
          &%{
            "personalShare" => &1["otherShare"],
            "otherShare" => &1["personalShare"],
            "balance" => -&1["balance"]
          }
        )

      peer_repayments =
        Enum.map(e["repayments"], &Map.update!(&1, "paidByUser", fn payer -> !payer end))

      peer = MoneyTrack.SharedMath.summarize(peer_expenses, peer_repayments)
      assert peer["balance"] == -result["balance"]
      assert peer["personalSpending"] == result["otherSpending"]

      assert MoneyTrack.SharedMath.summarize(
               Enum.reverse(expenses),
               Enum.reverse(e["repayments"])
             ) == result
    end
  end

  test "repayment amounts must be positive; aggregate totals cannot wrap" do
    for amount <- [0, -1, 100_000_000_000, 10.5] do
      assert_raise FunctionClauseError, fn ->
        MoneyTrack.SharedMath.summarize([], [%{"amount" => amount, "paidByUser" => true}])
      end
    end

    maximum = %{"personalShare" => 0, "otherShare" => 0, "balance" => 9_223_372_036_854_775_807}

    assert_raise ArgumentError, fn ->
      MoneyTrack.SharedMath.summarize([maximum], [%{"amount" => 1, "paidByUser" => true}])
    end

    offset = Map.update!(maximum, "balance", &(-&1))

    assert MoneyTrack.SharedMath.summarize([maximum, maximum, offset], [])["balance"] ==
             maximum["balance"]

    assert MoneyTrack.SharedMath.summarize([offset, maximum, maximum], [])["balance"] ==
             maximum["balance"]
  end
end
