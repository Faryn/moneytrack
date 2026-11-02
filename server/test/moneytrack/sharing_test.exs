defmodule MoneyTrack.SharingTest do
  use MoneyTrack.DataCase
  import MoneyTrack.Fixtures
  alias MoneyTrack.{Ledger, Sharing, Accounts}
  alias MoneyTrack.Accounts.VerifiedEmail

  defp people do
    a = user()
    b = user()
    outsider = user()
    email = "#{b.username}@example.org"
    Repo.insert!(%VerifiedEmail{user_id: b.id, address: email, verified_at: DateTime.utc_now()})
    {a, b, outsider, email}
  end

  defp share(a, email) do
    category =
      case Repo.get_by(MoneyTrack.Ledger.Category, user_id: a.id, name_key: "private restaurants") do
        nil -> elem(category(a, "Private restaurants"), 0)
        c -> Ledger.envelope(c)
      end

    p = expense(category["entityID"])
    {:ok, source} = Ledger.apply_operation(a, operation("expense", p))

    op =
      operation("shared_expense", %{
        "id" => source["entityID"],
        "command" => "share",
        "sourceRevision" => 1,
        "recipientEmail" => email,
        "paidByCreator" => true,
        "creatorSplit" => "half"
      })

    {:ok, shared} = Ledger.apply_operation(a, op)
    {shared, op}
  end

  defp accept(b, e) do
    {:ok, e} =
      Ledger.apply_operation(
        b,
        operation(
          "shared_expense",
          %{"id" => e["entityID"], "command" => "accept"},
          e["revision"]
        )
      )

    e
  end

  test "pending budgets, verified acceptance, private categories, replay and connection reuse" do
    {a, b, outsider, email} = people()
    {pending, op} = share(a, email)
    assert pending["payload"]["status"] == "pending"
    assert [e] = Ledger.snapshot(a).expenses
    assert e.personal_share == 3900
    assert Ledger.snapshot(b).expenses == []
    assert {:ok, ^pending} = Ledger.apply_operation(a, op)
    assert Repo.aggregate(Sharing.SharedExpense, :count) == 1
    {:ok, feed} = Ledger.changes(b)
    assert [invitation] = feed.changes
    assert invitation["entity"] == "sharing_invitation"
    refute Map.has_key?(invitation["payload"], "amount")

    assert {:error, :not_found} =
             Ledger.apply_operation(
               outsider,
               operation("shared_expense", %{"id" => e.id, "command" => "accept"}, 1)
             )

    accepted = accept(b, pending)
    assert accepted["payload"]["categoryID"] != e.category_id
    assert [other] = Ledger.snapshot(b).expenses
    assert other.personal_share == 3900
    assert Repo.get!(MoneyTrack.Ledger.Category, other.category_id).name == "Uncategorized"
    assert [%{amount: 0}] = Ledger.snapshot(b).budgets
    refute Jason.encode!(accepted) =~ "Private restaurants"
    {second, _} = share(a, email)
    assert second["payload"]["status"] == "accepted"
    assert second["payload"]["connection"]["id"] == accepted["payload"]["connection"]["id"]
    assert Repo.aggregate(Sharing.Connection, :count) == 1
    assert Repo.aggregate(Sharing.MailJob, :count) == 1
  end

  test "common conflicts and private assignments do not cross permissions or shared history" do
    {a, b, outsider, email} = people()
    {pending, _} = share(a, email)
    accepted = accept(b, pending)
    id = accepted["entityID"]
    {private, _} = category(b, "B private category")

    assignment =
      operation("shared_assignment", %{"id" => id, "categoryID" => private["entityID"]}, 1)

    assert {:ok, _} = Ledger.apply_operation(b, assignment)
    assert {:error, :not_found} = Ledger.apply_operation(outsider, assignment)
    {:ok, page} = Ledger.changes(a)
    refute Jason.encode!(page) =~ "B private category"

    edit =
      accepted["payload"]
      |> Map.take(~w(id amount description day paidByCreator creatorSplit))
      |> Map.put("description", "Updated by B")

    assert {:ok, changed} =
             Ledger.apply_operation(b, operation("shared_expense", edit, accepted["revision"]))

    assert {:error, {:conflict, current}} =
             Ledger.apply_operation(a, operation("shared_expense", edit, accepted["revision"]))

    assert current["revision"] == changed["revision"]
    refute Jason.encode!(current["payload"]["history"]) =~ "category"

    assert {:error, :not_found} =
             Ledger.apply_operation(
               outsider,
               operation("shared_expense", edit, changed["revision"])
             )
  end

  test "partial and full recording is retry-safe, budget-neutral and rejects stale balances" do
    {a, b, _, email} = people()
    {pending, _} = share(a, email)
    e = accept(b, pending)
    c = e["payload"]["connection"]["id"]
    assert Sharing.balance(a, c) == 3900

    p = %{
      "id" => Ecto.UUID.generate(),
      "connectionID" => c,
      "payerID" => b.id,
      "amount" => 1500,
      "day" => %{"year" => 2027, "month" => 1, "day" => 1},
      "createdAt" => "2027-01-01T12:00:00Z",
      "balanceAtConfirmation" => 3900
    }

    op = operation("repayment", p)

    for invalid <- [
          Map.put(p, "payerID", a.id),
          Map.put(p, "amount", 3901),
          Map.put(p, "amount", 0)
        ] do
      assert {:error, {:validation, _}} =
               Ledger.apply_operation(a, operation("repayment", invalid))
    end

    assert Sharing.balance(a, c) == 3900
    assert Repo.aggregate(Sharing.Repayment, :count) == 0
    assert {:ok, repaid} = Ledger.apply_operation(a, op)
    assert {:ok, ^repaid} = Ledger.apply_operation(a, op)
    assert Sharing.balance(a, c) == 2400
    assert Sharing.balance(b, c) == -2400
    assert [expense] = Ledger.snapshot(a).expenses
    assert expense.personal_share == 3900
    stale = Map.put(p, "id", Ecto.UUID.generate())
    assert {:error, {:validation, _}} = Ledger.apply_operation(a, operation("repayment", stale))

    full =
      p
      |> Map.put("id", Ecto.UUID.generate())
      |> Map.put("amount", 2400)
      |> Map.put("balanceAtConfirmation", -2400)

    assert {:ok, _} = Ledger.apply_operation(b, operation("repayment", full))
    assert Sharing.balance(a, c) == 0
    assert Repo.aggregate(Sharing.Repayment, :count) == 2

    assert {:ok, deleted} =
             Ledger.apply_operation(
               a,
               operation("shared_expense", %{"id" => e["entityID"]}, e["revision"], "delete")
             )

    assert deleted["deleted"]
    assert Ledger.snapshot(a).expenses == []
    assert Ledger.snapshot(b).expenses == []
    assert Sharing.balance(a, c) == -3900
    assert Repo.aggregate(Sharing.Repayment, :count) == 2
  end

  test "unverified address gets its invitation only after mailbox proof; rollback is atomic" do
    a = user()
    b = user()
    email = "#{b.username}@example.org"
    {pending, _} = share(a, email)
    assert {:ok, %{changes: []}} = Ledger.changes(b)
    id = Ecto.UUID.generate()
    assert {:ok, _} = Accounts.EmailVerification.request(b, email, id)
    MoneyTrack.MailDelivery.deliver_pending()
    assert_receive {:email, mail}
    # Queue can also contain the invitation; locate the ownership message.
    mail =
      if String.contains?(mail.text_body, "code is"),
        do: mail,
        else:
          (receive do
             {:email, m} -> m
           end)

    [_, code] = Regex.run(~r/code is ([0-9]{8})/, mail.text_body)
    assert {:ok, _} = Accounts.EmailVerification.verify(b, id, code)
    assert Sharing.snapshot(b).invitations != []

    assert {:error, :rollback} =
             Repo.transaction(fn ->
               accept(b, pending)
               Repo.rollback(:rollback)
             end)

    assert Repo.aggregate(Sharing.Connection, :count) == 0
    assert [expense] = Ledger.snapshot(a).expenses
    assert expense.personal_share == 3900
    assert Ledger.snapshot(b).expenses == []
  end
end
