defmodule MoneyTrack.Ledger do
  @moduledoc "Owner-scoped personal ledger and transactional sync operations."
  import Ecto.Query
  import Ecto.Changeset
  alias MoneyTrack.Repo
  alias MoneyTrack.Accounts.User
  alias MoneyTrack.Ledger.{Category, YearBudget, Expense, ProcessedOperation, UserChange}
  @maximum 99_999_999_999
  @operation_fields ~w(operationID entity entityID action expectedRevision payload)

  def apply_operation(%User{} = user, operation) when is_map(operation) do
    with true <- Enum.sort(Map.keys(operation)) == Enum.sort(@operation_fields),
         {:ok, operation_id} <- Ecto.UUID.cast(operation["operationID"]),
         {:ok, entity_id} <- Ecto.UUID.cast(operation["entityID"]),
         true <- operation["entity"] in ["category", "year_budget", "expense"],
         true <- operation["action"] in ["upsert", "delete"],
         true <- is_integer(operation["expectedRevision"]) and operation["expectedRevision"] >= 0,
         true <- is_map(operation["payload"]),
         {:ok, ^entity_id} <- Ecto.UUID.cast(operation["payload"]["id"]) do
      fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary(canonical(operation)))

      result =
        Repo.transaction(fn ->
          case Repo.get_by(ProcessedOperation, user_id: user.id, operation_id: operation_id) do
            %ProcessedOperation{fingerprint: ^fingerprint, result: record} ->
              {record, false}

            %ProcessedOperation{} ->
              Repo.rollback(:operation_reused)

            nil ->
              record = mutate(user, entity_id, operation)

              sequence =
                (Repo.one(
                   from c in UserChange, where: c.user_id == ^user.id, select: max(c.sequence)
                 ) || 0) + 1

              Repo.insert!(%UserChange{user_id: user.id, sequence: sequence, record: record})

              Repo.insert!(%ProcessedOperation{
                user_id: user.id,
                operation_id: operation_id,
                fingerprint: fingerprint,
                result: record
              })

              {record, true}
          end
        end)

      case result do
        {:ok, {record, changed}} ->
          if changed,
            do: Phoenix.PubSub.broadcast(MoneyTrack.PubSub, "ledger:#{user.id}", :ledger_changed)

          {:ok, record}

        {:error, reason} ->
          {:error, reason}
      end
    else
      _ -> {:error, :invalid_operation}
    end
  end

  def apply_operation(_, _), do: {:error, :invalid_operation}

  def changes(%User{} = user, cursor \\ nil) do
    with {:ok, after_sequence, through} <- decode_cursor(user, cursor) do
      through =
        through ||
          Repo.one(from c in UserChange, where: c.user_id == ^user.id, select: max(c.sequence)) ||
          0

      rows =
        Repo.all(
          from c in UserChange,
            where:
              c.user_id == ^user.id and c.sequence > ^after_sequence and c.sequence <= ^through,
            order_by: c.sequence,
            limit: 101
        )

      page = Enum.take(rows, 100)

      last =
        case List.last(page) do
          nil -> after_sequence
          row -> row.sequence
        end

      more = length(rows) > 100

      next =
        Phoenix.Token.sign(MoneyTrackWeb.Endpoint, "ledger-cursor", %{
          user: user.id,
          after: last,
          through: if(more, do: through)
        })

      {:ok, %{changes: Enum.map(page, & &1.record), cursor: next, hasMore: more}}
    end
  end

  def snapshot(%User{} = user) do
    {:ok, snapshot} =
      Repo.transaction(fn ->
        %{
          categories:
            Repo.all(from c in Category, where: c.user_id == ^user.id, order_by: c.name_key),
          budgets: Repo.all(from b in YearBudget, where: b.user_id == ^user.id),
          expenses:
            Repo.all(
              from e in Expense,
                where: e.user_id == ^user.id and is_nil(e.deleted_at),
                order_by: [desc: e.expense_date, desc: e.inserted_at]
            )
        }
      end)

    snapshot
  end

  def envelope(%Category{} = c), do: record("category", c, %{"id" => c.id, "name" => c.name})

  def envelope(%YearBudget{} = b),
    do:
      record("year_budget", b, %{
        "id" => b.id,
        "categoryID" => b.category_id,
        "year" => b.year,
        "amount" => b.amount
      })

  def envelope(%Expense{} = e) do
    record("expense", e, %{
      "id" => e.id,
      "categoryID" => e.category_id,
      "amount" => e.amount,
      "personalShare" => e.personal_share,
      "description" => e.description,
      "day" => %{
        "year" => e.expense_date.year,
        "month" => e.expense_date.month,
        "day" => e.expense_date.day
      },
      "createdAt" => DateTime.to_iso8601(e.client_created_at)
    })
  end

  defp record(entity, value, payload),
    do: %{
      "entity" => entity,
      "entityID" => value.id,
      "revision" => value.revision,
      "deleted" => not is_nil(Map.get(value, :deleted_at)),
      "payload" => payload
    }

  defp mutate(user, id, op) do
    schema =
      case op["entity"] do
        "category" -> Category
        "year_budget" -> YearBudget
        "expense" -> Expense
      end

    existing = Repo.get(schema, id)
    if existing && existing.user_id != user.id, do: Repo.rollback(:not_found)
    if is_nil(existing) && op["expectedRevision"] > 0, do: Repo.rollback(:not_found)
    revision = if existing, do: existing.revision, else: 0

    if op["expectedRevision"] != revision,
      do: Repo.rollback({:conflict, if(existing, do: envelope(existing))})

    if match?(%Expense{deleted_at: deleted} when not is_nil(deleted), existing),
      do: Repo.rollback({:conflict, envelope(existing)})

    changeset =
      if op["action"] == "delete" do
        if schema != Expense || is_nil(existing), do: Repo.rollback(:not_found)
        unless keys?(op["payload"], ~w(id deletedAt)), do: Repo.rollback(:invalid_operation)
        change(existing, deleted_at: DateTime.utc_now())
      else
        attrs = attributes(user, op["entity"], op["payload"])

        if schema == YearBudget do
          if existing &&
               (existing.category_id != attrs.category_id || existing.year != attrs.year),
             do:
               Repo.rollback(
                 {:validation, "A yearly budget belongs to one category and calendar year."}
               )

          other =
            Repo.get_by(YearBudget,
              user_id: user.id,
              category_id: attrs.category_id,
              year: attrs.year
            )

          if !existing && other, do: Repo.rollback({:conflict, envelope(other)})
        end

        base = existing || struct(schema, id: id, user_id: user.id)

        if existing && schema == Expense && attrs.client_created_at != existing.client_created_at,
          do: Repo.rollback({:validation, "The expense creation timestamp cannot change."})

        changeset = change(base, attrs)

        case schema do
          Category ->
            unique_constraint(changeset, :name_key, name: :categories_user_id_name_key_index)

          YearBudget ->
            changeset
            |> unique_constraint(:year, name: :year_budgets_user_id_category_id_year_index)
            |> foreign_key_constraint(:category_id)
            |> check_constraint(:amount, name: :valid_budget)

          Expense ->
            changeset
            |> foreign_key_constraint(:category_id)
            |> check_constraint(:amount, name: :valid_expense)
        end
      end

    changeset = if existing, do: optimistic_lock(changeset, :revision), else: changeset

    outcome =
      if existing,
        do: Repo.update(changeset, stale_error_field: :revision),
        else: Repo.insert(changeset)

    case outcome do
      {:ok, saved} ->
        envelope(saved)

      {:error, changeset} ->
        if Keyword.has_key?(changeset.errors, :revision),
          do: Repo.rollback({:conflict, envelope(Repo.get!(schema, id))})

        Repo.rollback(
          {:validation,
           "Check the fields. Category names and category/year budgets must be unique."}
        )
    end
  end

  defp attributes(_user, "category", payload) do
    name = payload["name"]

    unless keys?(payload, ~w(id name)) && is_binary(name) &&
             String.length(String.trim(name)) in 1..100,
           do: Repo.rollback({:validation, "Enter a category name of 1–100 characters."})

    name = String.trim(name)
    key = name |> String.normalize(:nfd) |> String.replace(~r/\p{Mn}/u, "") |> String.downcase()
    %{name: name, name_key: key}
  end

  defp attributes(user, "year_budget", payload) do
    unless keys?(payload, ~w(id categoryID year amount)) && is_integer(payload["year"]) &&
             payload["year"] in 1900..9999 && valid_money?(payload["amount"], true),
           do: Repo.rollback({:validation, "Enter a valid yearly budget in exact cents."})

    %{
      category_id: owned_category!(user, payload["categoryID"]),
      year: payload["year"],
      amount: payload["amount"]
    }
  end

  defp attributes(user, "expense", payload) do
    day = payload["day"]

    unless keys?(payload, ~w(id categoryID amount personalShare description day createdAt)) &&
             valid_money?(payload["amount"], false) &&
             payload["personalShare"] === payload["amount"] && is_binary(payload["description"]) &&
             String.length(payload["description"]) <= 500 &&
             is_map(day) && keys?(day, ~w(year month day)) &&
             Enum.all?(Map.values(day), &is_integer/1) && day["year"] in 1900..9999,
           do: Repo.rollback({:validation, "Enter a valid personal expense, date, and category."})

    date =
      case Date.new(day["year"], day["month"], day["day"]) do
        {:ok, date} -> date
        _ -> Repo.rollback({:validation, "Choose a valid calendar date."})
      end

    created =
      case payload["createdAt"] do
        value when is_binary(value) ->
          case DateTime.from_iso8601(value) do
            {:ok, date, _} -> DateTime.truncate(date, :second)
            _ -> Repo.rollback(:invalid_operation)
          end

        _ ->
          Repo.rollback(:invalid_operation)
      end

    %{
      category_id: owned_category!(user, payload["categoryID"]),
      amount: payload["amount"],
      personal_share: payload["amount"],
      description: String.trim(payload["description"]),
      expense_date: date,
      client_created_at: created,
      currency: "EUR"
    }
  end

  defp owned_category!(user, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Category{} <- Repo.get_by(Category, id: id, user_id: user.id),
         do: id,
         else: (_ -> Repo.rollback(:not_found))
  end

  defp valid_money?(amount, allow_zero),
    do: is_integer(amount) && amount in if(allow_zero, do: 0, else: 1)..@maximum

  defp keys?(map, keys), do: Enum.sort(Map.keys(map)) == Enum.sort(keys)

  defp canonical(value) when is_map(value),
    do: value |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(fn {k, v} -> {k, canonical(v)} end)

  defp canonical(value) when is_list(value), do: Enum.map(value, &canonical/1)
  defp canonical(value), do: value

  defp decode_cursor(_user, cursor) when cursor in [nil, ""], do: {:ok, 0, nil}

  defp decode_cursor(user, cursor) when is_binary(cursor) and byte_size(cursor) < 2048 do
    with {:ok, %{user: id, after: after_sequence, through: through}} <-
           Phoenix.Token.verify(MoneyTrackWeb.Endpoint, "ledger-cursor", cursor,
             max_age: :infinity
           ),
         true <-
           id == user.id && is_integer(after_sequence) && after_sequence >= 0 &&
             (is_nil(through) || (is_integer(through) && through >= after_sequence)) do
      {:ok, after_sequence, through}
    else
      _ -> {:error, :invalid_cursor}
    end
  end

  defp decode_cursor(_, _), do: {:error, :invalid_cursor}
end
