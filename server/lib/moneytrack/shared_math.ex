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
end
