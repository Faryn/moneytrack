defmodule MoneyTrack.CurrencyTest do
  use MoneyTrack.DataCase
  import MoneyTrack.Fixtures
  alias MoneyTrack.{Currency, Ledger, Sharing}

  defp fx(amount, currency, rate),
    do: %{
      "originalAmount" => amount,
      "originalCurrency" => currency,
      "rate" => rate,
      "rateDate" => "2026-11-03",
      "source" => "ECB"
    }

  test "ECB feed preserves published decimal strings" do
    assert {:ok, %{date: "2026-11-03", rates: %{"USD" => "1.11790"}}} =
             Currency.decode_rates(
               "<Envelope><Cube time='2026-11-03'><Cube currency='USD' rate='1.11790'/></Cube></Envelope>"
             )

    assert {:error, _} = Currency.decode_rates("<broken>")
  end

  test "exact conversion rounds once, then shares and repayments conserve euro cents" do
    for {original, currency, rate, euro, other} <- [
          {12345, "USD", "1.25", 9876, 4938},
          {1, "USD", "2", 1, 0},
          {1000, "JPY", "150", 667, 333},
          {15000, "KRW", "1500", 1000, 500},
          {1000, "ISK", "150", 667, 333}
        ] do
      assert {:ok, ^euro} = Currency.euro_cents(fx(original, currency, rate))
      shares = MoneyTrack.SharedMath.calculate(euro, "half", true)
      assert shares["balance"] == other
    end

    assert {:error, _} = Currency.euro_cents(fx(100, "USD", "0"))
    assert {:error, _} = Currency.euro_cents(fx(100, "XXX", "1"))
  end

  test "conversion survives duplicate personal write, sharing, edits, and both feeds" do
    a = user()
    b = user()
    email = "#{b.username}@example.org"

    Repo.insert!(%MoneyTrack.Accounts.VerifiedEmail{
      user_id: b.id,
      address: email,
      verified_at: DateTime.utc_now()
    })

    {cat, _} = category(a)
    conversion = fx(1000, "JPY", "150")
    payload = expense(cat["entityID"], 667) |> Map.put("conversion", conversion)
    op = operation("expense", payload)
    assert {:ok, saved} = Ledger.apply_operation(a, op)
    assert {:ok, ^saved} = Ledger.apply_operation(a, op)
    assert saved["payload"]["conversion"] == conversion
    bad = payload |> Map.put("amount", 668) |> Map.put("personalShare", 668)
    assert {:error, {:validation, _}} = Ledger.apply_operation(a, operation("expense", bad, 1))

    assert {:ok, shared} =
             Ledger.apply_operation(
               a,
               operation("shared_expense", %{
                 "id" => payload["id"],
                 "command" => "share",
                 "sourceRevision" => 1,
                 "recipientEmail" => email,
                 "paidByCreator" => true,
                 "creatorSplit" => "half"
               })
             )

    assert shared["payload"]["conversion"] == conversion

    assert {:ok, accepted} =
             Ledger.apply_operation(
               b,
               operation("shared_expense", %{"id" => payload["id"], "command" => "accept"}, 1)
             )

    assert accepted["payload"]["conversion"] == conversion
    connection = accepted["payload"]["connection"]["id"]
    assert Sharing.balance(a, connection) == 333

    repayment = %{
      "id" => Ecto.UUID.generate(),
      "connectionID" => connection,
      "payerID" => b.id,
      "recipientID" => a.id,
      "amount" => 100,
      "balanceAtConfirmation" => 333,
      "day" => %{"year" => 2026, "month" => 11, "day" => 4},
      "createdAt" => "2026-11-04T12:00:00Z"
    }

    assert {:ok, _} = Ledger.apply_operation(a, operation("repayment", repayment))
    assert Sharing.balance(a, connection) == 233
    assert hd(Sharing.projected_expenses(a)).personal_share == 334
    assert hd(Sharing.projected_expenses(b)).personal_share == 333
    assert Ledger.has_conversion?(a)
    assert Ledger.has_conversion?(b)
  end
end
