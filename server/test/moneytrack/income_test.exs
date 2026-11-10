defmodule MoneyTrack.IncomeTest do
  use MoneyTrack.DataCase
  import MoneyTrack.Fixtures
  alias MoneyTrack.{Ledger, Repo}

  test "income is private, duplicate-safe, versioned and synchronized through deletion" do
    user = user()
    other = user()
    {category, _} = category(user)
    payload = expense(category["entityID"], 200_000) |> Map.put("kind", "income")
    op = operation("expense", payload)
    assert {:ok, record} = Ledger.apply_operation(user, op)
    assert record["payload"]["kind"] == "income"
    assert {:ok, ^record} = Ledger.apply_operation(user, op)
    assert length(Ledger.snapshot(user).expenses) == 1
    assert Ledger.snapshot(other).expenses == []
    assert {:error, :not_found} = Ledger.apply_operation(other, operation("expense", payload, 1))

    assert {:error, {:conflict, ^record}} =
             Ledger.apply_operation(user, operation("expense", payload, 0))

    assert {:error, {:validation, _}} =
             Ledger.apply_operation(user, operation("expense", Map.delete(payload, "kind"), 1))

    updated = Map.put(payload, "description", "Salary corrected")
    assert {:ok, edited} = Ledger.apply_operation(user, operation("expense", updated, 1))
    assert edited["revision"] == 2
    assert edited["payload"]["kind"] == "income"

    delete =
      operation(
        "expense",
        %{"id" => payload["id"], "deletedAt" => "2026-11-05T00:00:00Z"},
        2,
        "delete"
      )

    assert {:ok, deleted} = Ledger.apply_operation(user, delete)
    assert deleted["deleted"]
    assert deleted["payload"]["kind"] == "income"
    assert {:ok, ^deleted} = Ledger.apply_operation(user, delete)
    assert Ledger.snapshot(user).expenses == []
    assert Ledger.has_income?(user)
    assert {:ok, page} = Ledger.changes(user)
    assert List.last(page.changes) == deleted

    assert {:error, {:conflict, ^deleted}} =
             Ledger.apply_operation(user, operation("expense", updated, 3))
  end

  test "income does not consume category or whole-year budgets, including prior-month carry" do
    entries = [
      %{
        "kind" => "expense",
        "amount" => 2500,
        "personalShare" => 2500,
        "day" => "2026-01-15",
        "categoryID" => "food"
      },
      %{
        "kind" => "income",
        "amount" => 300_000,
        "personalShare" => 300_000,
        "day" => "2026-01-31",
        "categoryID" => "food"
      },
      %{
        "kind" => "income",
        "amount" => 100_000,
        "personalShare" => 100_000,
        "day" => "2026-02-01",
        "categoryID" => "salary"
      }
    ]

    only_expenses = Enum.reject(entries, &(&1["kind"] == "income"))

    assert MoneyTrack.Budget.for_category(2026, 2, 120_000, entries) ==
             MoneyTrack.Budget.for_category(2026, 2, 120_000, only_expenses)

    plan = [%{"categoryID" => "food", "amount" => 60000}]

    assert MoneyTrack.Budget.for_plan(2026, 2, 120_000, plan, "free", entries) ==
             MoneyTrack.Budget.for_plan(2026, 2, 120_000, plan, "free", only_expenses)
  end

  test "type must be recognized, can be changed explicitly, and cannot be shared" do
    user = user()
    {category, _} = category(user)
    payload = expense(category["entityID"]) |> Map.put("kind", "income")

    for invalid <- [nil, "refund", 1, false] do
      assert {:error, _} =
               Ledger.apply_operation(
                 user,
                 operation("expense", Map.put(payload, "kind", invalid))
               )
    end

    assert {:ok, _} = Ledger.apply_operation(user, operation("expense", payload))

    share = %{
      "id" => payload["id"],
      "command" => "share",
      "sourceRevision" => 1,
      "recipientEmail" => "other@example.invalid",
      "paidByCreator" => true,
      "creatorSplit" => "half"
    }

    assert {:error, {:validation, "Income cannot be shared."}} =
             Ledger.apply_operation(user, operation("shared_expense", share))

    assert Repo.aggregate(MoneyTrack.Sharing.SharedExpense, :count) == 0

    assert {:ok, as_expense} =
             Ledger.apply_operation(
               user,
               operation("expense", Map.put(payload, "kind", "expense"), 1)
             )

    refute Map.has_key?(as_expense["payload"], "kind")
    assert {:ok, as_income} = Ledger.apply_operation(user, operation("expense", payload, 2))
    assert as_income["payload"]["kind"] == "income"
  end

  test "income preserves original currency provenance" do
    user = user()
    {category, _} = category(user)

    conversion = %{
      "originalAmount" => 1000,
      "originalCurrency" => "JPY",
      "rate" => "150",
      "rateDate" => "2026-11-03",
      "source" => "ECB"
    }

    payload =
      expense(category["entityID"], 667)
      |> Map.merge(%{"kind" => "income", "conversion" => conversion})

    assert {:ok, saved} = Ledger.apply_operation(user, operation("expense", payload))
    assert saved["payload"]["conversion"] == conversion
    assert saved["payload"]["kind"] == "income"
  end
end
