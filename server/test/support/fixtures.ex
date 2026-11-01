defmodule MoneyTrack.Fixtures do
  alias MoneyTrack.{Accounts, Ledger}
  def password, do: "fixture-passphrase-2026"

  def user do
    {:ok, user} =
      Accounts.create_user(%{
        username: "user#{System.unique_integer([:positive])}",
        password: password()
      })

    user
  end

  def operation(entity, payload, revision \\ 0, action \\ "upsert") do
    %{
      "operationID" => Ecto.UUID.generate(),
      "entity" => entity,
      "entityID" => payload["id"],
      "action" => action,
      "expectedRevision" => revision,
      "payload" => payload
    }
  end

  def category(user, name \\ "Restaurants") do
    op = operation("category", %{"id" => Ecto.UUID.generate(), "name" => name})
    {:ok, record} = Ledger.apply_operation(user, op)
    {record, op}
  end

  def expense(category_id, amount \\ 7800) do
    %{
      "id" => Ecto.UUID.generate(),
      "categoryID" => category_id,
      "amount" => amount,
      "personalShare" => amount,
      "description" => "Theodor",
      "day" => %{"year" => 2026, "month" => 1, "day" => 15},
      "createdAt" => "2026-01-15T12:00:00Z"
    }
  end
end
