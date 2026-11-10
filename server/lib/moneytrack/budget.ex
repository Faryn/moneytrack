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
        share = if expense["kind"] == "income", do: 0, else: expense["personalShare"]

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

  def joint_allocations(total, allocations, default_id) do
    parts =
      Enum.sort_by(allocations, & &1["categoryID"]) ++
        [
          %{
            "categoryID" => default_id,
            "amount" => total - Enum.sum(Enum.map(allocations, & &1["amount"]))
          }
        ]

    base = Enum.sum(Enum.map(parts, &div(&1["amount"], 12)))

    capacity =
      Map.new(0..11, fn month ->
        {month, div(total, 12) + if(month < rem(total, 12), do: 1, else: 0) - base}
      end)

    {result, _} =
      Enum.reduce(parts, {%{}, capacity}, fn p, {result, capacity} ->
        months = Enum.sort_by(0..11, &{-capacity[&1], &1}) |> Enum.take(rem(p["amount"], 12))
        cells = for m <- 0..11, do: div(p["amount"], 12) + if(m in months, do: 1, else: 0)

        capacity =
          Enum.reduce(months, capacity, fn m, c ->
            if c[m] <= 0, do: raise(ArgumentError, "overallocated budget")
            Map.update!(c, m, &(&1 - 1))
          end)

        {Map.put(result, p["categoryID"], cells), capacity}
      end)

    result
  end

  def for_plan(year, month, total, allocations, default_id, expenses) do
    monthly = joint_allocations(total, allocations, default_id)
    allocated_ids = Enum.map(allocations, & &1["categoryID"])

    assigned_months =
      for m <- 0..11, do: Enum.sum(Enum.map(allocated_ids, &Enum.at(monthly[&1], m)))

    unbudgeted = Enum.reject(expenses, &(&1["categoryID"] in allocated_ids))

    category_results =
      Map.new(allocations, fn a ->
        {a["categoryID"],
         for_schedule(
           year,
           month,
           monthly[a["categoryID"]],
           Enum.filter(expenses, &(&1["categoryID"] == a["categoryID"]))
         )}
      end)

    %{
      "total" => for_schedule(year, month, assigned_months, expenses),
      "unallocated" => Enum.sum(monthly[default_id]),
      "unbudgeted" => for_category(year, month, 0, unbudgeted),
      "categories" => category_results
    }
  end

  defp for_schedule(year, month, schedule, expenses) do
    result = for_category(year, month, 0, expenses)
    carry = Enum.sum(Enum.take(schedule, month - 1)) + result["carryover"]
    allocation = Enum.at(schedule, month - 1)

    %{
      "allocation" => allocation,
      "carryover" => carry,
      "spent" => result["spent"],
      "remaining" => allocation + carry - result["spent"]
    }
  end
end
