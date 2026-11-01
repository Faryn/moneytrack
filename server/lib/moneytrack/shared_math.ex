defmodule MoneyTrack.SharedMath do
  @moduledoc "Exact two-person expense shares; positive balance means money owed to the viewer."
  @maximum 99_999_999_999

  def calculate(amount, split, paid_by_user)
      when is_integer(amount) and amount in 1..@maximum and split in ["all", "half", "none"] and
             is_boolean(paid_by_user) do
    own =
      case split do
        "all" -> amount
        "none" -> 0
        "half" -> div(amount, 2) + if(paid_by_user, do: rem(amount, 2), else: 0)
      end

    %{
      "personalShare" => own,
      "otherShare" => amount - own,
      "balance" => if(paid_by_user, do: amount, else: 0) - own
    }
  end

  @doc "Shared balance after recorded repayments; repayments never contribute to expense spending."
  def summarize(expenses, repayments) when is_list(expenses) and is_list(repayments) do
    personal = Enum.sum(Enum.map(expenses, & &1["personalShare"]))
    other = Enum.sum(Enum.map(expenses, & &1["otherShare"]))
    expense_balance = Enum.sum(Enum.map(expenses, & &1["balance"]))

    balance =
      expense_balance +
        Enum.sum(Enum.map(repayments, &repayment_change(&1["amount"], &1["paidByUser"])))

    result = %{
      "personalSpending" => personal,
      "otherSpending" => other,
      "expenseBalance" => expense_balance,
      "balance" => balance
    }

    # Match the native client's exact signed 64-bit aggregate range.
    if Enum.any?(
         Map.values(result),
         &(&1 < -9_223_372_036_854_775_808 or &1 > 9_223_372_036_854_775_807)
       ),
       do: raise(ArgumentError, "shared total exceeds supported range")

    result
  end

  defp repayment_change(amount, paid_by_user)
       when is_integer(amount) and amount in 1..@maximum and is_boolean(paid_by_user),
       do: if(paid_by_user, do: amount, else: -amount)
end
