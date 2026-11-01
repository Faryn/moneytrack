defmodule MoneyTrack.Budget do
  @moduledoc """
  Calendar-year budget arithmetic in integer minor currency units.

  This pure calculation matches the native iOS implementation. It does not
  introduce an API, financial database records, or shared-expense permissions.
  """

  def cumulative_allocation(annual, month)
      when is_integer(annual) and annual >= 0 and month in 0..12 do
    div(annual, 12) * month + min(rem(annual, 12), month)
  end

  def for_category(year, month, annual, expenses) when month in 1..12 do
    {before, spent} =
      Enum.reduce(expenses, {0, 0}, fn expense, {before, spent} ->
        day = Date.from_iso8601!(expense["day"])
        share = expense["personalShare"]

        unless is_integer(share) and share >= 0 and share <= expense["amount"] do
          raise ArgumentError, "invalid personal share"
        end

        cond do
          day.year != year -> {before, spent}
          day.month < month -> {before + share, spent}
          day.month == month -> {before, spent + share}
          true -> {before, spent}
        end
      end)

    prior = cumulative_allocation(annual, month - 1)
    allocation = cumulative_allocation(annual, month) - prior
    carryover = prior - before

    %{
      "allocation" => allocation,
      "carryover" => carryover,
      "spent" => spent,
      "remaining" => allocation + carryover - spent
    }
  end
end
