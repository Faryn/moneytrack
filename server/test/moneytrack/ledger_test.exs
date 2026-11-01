defmodule MoneyTrack.LedgerTest do
  use MoneyTrack.DataCase
  import MoneyTrack.Fixtures
  alias MoneyTrack.{Ledger, Repo}
  alias MoneyTrack.Ledger.{Expense, UserChange, ProcessedOperation}

  test "lost-response replay applies exactly once and rejects changed operation content" do
    user = user()
    {category, _} = category(user)
    op = operation("expense", expense(category["entityID"]))
    assert {:ok, record} = Ledger.apply_operation(user, op)
    assert {:ok, ^record} = Ledger.apply_operation(user, op)
    assert Repo.aggregate(Expense, :count) == 1
    assert Repo.aggregate(UserChange, :count) == 2
    assert Repo.aggregate(ProcessedOperation, :count) == 2
    changed = put_in(op, ["payload", "amount"], 500)
    assert {:error, :operation_reused} = Ledger.apply_operation(user, changed)
    assert Repo.get!(Expense, op["entityID"]).amount == 7800
  end

  test "ownership is enforced for entities, category references, and change cursors" do
    alice = user()
    bob = user()
    {category, category_op} = category(alice)

    assert {:error, :not_found} =
             Ledger.apply_operation(bob, %{category_op | "operationID" => Ecto.UUID.generate()})

    assert {:error, :not_found} =
             Ledger.apply_operation(bob, operation("expense", expense(category["entityID"])))

    {:ok, first} = Ledger.changes(alice)
    assert length(first.changes) == 1
    assert {:error, :invalid_cursor} = Ledger.changes(bob, first.cursor)
    assert {:ok, %{changes: []}} = Ledger.changes(bob)
  end

  test "stale edits conflict and tombstones cannot be resurrected" do
    user = user()
    {category, _} = category(user)
    payload = expense(category["entityID"])
    {:ok, original} = Ledger.apply_operation(user, operation("expense", payload))
    newer = %{payload | "amount" => 9800, "personalShare" => 9800}
    assert {:ok, updated} = Ledger.apply_operation(user, operation("expense", newer, 1))
    assert updated["revision"] == 2

    assert {:error, {:conflict, ^updated}} =
             Ledger.apply_operation(user, operation("expense", payload, 1))

    deletion =
      operation(
        "expense",
        %{"id" => payload["id"], "deletedAt" => "2026-01-16T00:00:00Z"},
        2,
        "delete"
      )

    assert {:ok, deleted} = Ledger.apply_operation(user, deletion)
    assert deleted["deleted"]
    assert {:ok, ^deleted} = Ledger.apply_operation(user, deletion)

    assert {:error, {:conflict, ^deleted}} =
             Ledger.apply_operation(user, operation("expense", payload, 3))

    assert Ledger.snapshot(user).expenses == []
    assert original["revision"] == 1
  end

  test "invalid financial fields and duplicate budgets roll back the whole operation" do
    user = user()
    {category, _} = category(user)
    payload = expense(category["entityID"])

    for invalid <- [
          put_in(payload["amount"], 78.5),
          put_in(payload["day"]["day"], 32),
          Map.put(payload, "owner", user.id),
          put_in(payload["personalShare"], 3900)
        ] do
      assert {:error, _} = Ledger.apply_operation(user, operation("expense", invalid))
    end

    assert Repo.aggregate(Expense, :count) == 0
    assert Repo.aggregate(UserChange, :count) == 1

    budget = %{
      "id" => Ecto.UUID.generate(),
      "categoryID" => category["entityID"],
      "year" => 2026,
      "amount" => 120_000
    }

    assert {:ok, _} = Ledger.apply_operation(user, operation("year_budget", budget))

    assert {:error, _} =
             Ledger.apply_operation(
               user,
               operation("year_budget", %{budget | "id" => Ecto.UUID.generate()})
             )

    assert {:error, _} =
             Ledger.apply_operation(
               user,
               operation("category", %{"id" => Ecto.UUID.generate(), "name" => "RESTAURANTS"})
             )

    assert Repo.aggregate(UserChange, :count) == 2
  end

  test "pagination freezes an upper boundary and catches later writes on the next cycle" do
    user = user()
    for i <- 1..101, do: category(user, "Category #{i}")
    {:ok, first} = Ledger.changes(user)
    assert length(first.changes) == 100
    assert first.hasMore
    {newest, _} = category(user, "After snapshot")
    {:ok, second} = Ledger.changes(user, first.cursor)
    assert length(second.changes) == 1
    refute second.hasMore
    {:ok, third} = Ledger.changes(user, second.cursor)
    assert third.changes == [newest]
    assert {:error, :invalid_cursor} = Ledger.changes(user, "forged-cursor")
  end
end
