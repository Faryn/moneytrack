defmodule MoneyTrack.Sharing do
  @moduledoc "Two-account shared facts, private assignments and recorded repayments. Writes run inside Ledger transactions."
  import Ecto.Query
  import Ecto.Changeset
  alias MoneyTrack.{Repo, Ledger, SharedMath}
  alias MoneyTrack.Accounts.{User, VerifiedEmail, EmailVerification}
  alias MoneyTrack.Ledger.{Expense, Category, YearBudget}

  alias MoneyTrack.Sharing.{
    Connection,
    SharedExpense,
    Assignment,
    History,
    InvitationReceipt,
    Repayment,
    MailJob
  }

  @maximum 99_999_999_999

  def has_data?(user) do
    email = Repo.get_by(VerifiedEmail, user_id: user.id)

    Repo.exists?(
      from e in SharedExpense, where: e.creator_id == ^user.id or e.recipient_id == ^user.id
    ) ||
      (email != nil &&
         Repo.exists?(
           from e in SharedExpense,
             where: e.recipient_email == ^email.address and e.status == "pending"
         ))
  end

  def mutate(user, id, %{"entity" => "shared_expense"} = op) do
    case op["payload"]["command"] do
      "share" -> create(user, id, op)
      "accept" -> accept(user, id, op)
      _ -> edit(user, id, op)
    end
  end

  def mutate(user, id, %{"entity" => "shared_assignment"} = op) do
    e = expense!(user, id)
    assignment = Repo.get_by!(Assignment, expense_id: id, user_id: user.id)

    if op["expectedRevision"] != assignment.revision,
      do: Repo.rollback({:conflict, assignment_envelope(assignment)})

    if op["action"] != "upsert" || e.deleted_at, do: Repo.rollback(:not_found)
    category = owned_category!(user, op["payload"]["categoryID"])

    saved =
      assignment
      |> change(category_id: category, revision: assignment.revision + 1)
      |> Repo.update!()

    assignment_envelope(saved)
  end

  def mutate(user, id, %{"entity" => "repayment"} = op) do
    if existing = Repo.get(Repayment, id) do
      if participant?(user, Repo.get!(Connection, existing.connection_id)),
        do: Repo.rollback({:conflict, repayment_envelope(user, existing)}),
        else: Repo.rollback(:not_found)
    end

    p = op["payload"]
    c = connection!(user, p["connectionID"])
    payer = uuid!(p["payerID"])
    recipient = other_id(c, payer)

    unless payer in [c.user_low, c.user_high] && op["expectedRevision"] == 0 &&
             op["action"] == "upsert" && money?(p["amount"]),
           do: invalid!("Enter a valid repayment amount.")

    balance = balance(user, c.id)

    unless p["balanceAtConfirmation"] === balance && balance != 0 && p["amount"] <= abs(balance) &&
             payer == if(balance < 0, do: user.id, else: other_id(c, user.id)),
           do:
             invalid!(
               "The shared balance changed. Refresh activity and record the repayment again."
             )

    value =
      Repo.insert!(%Repayment{
        id: id,
        connection_id: c.id,
        payer_id: payer,
        recipient_id: recipient,
        actor_id: user.id,
        amount: p["amount"],
        repayment_date: day!(p["day"]),
        client_created_at: created!(p["createdAt"])
      })

    peer = Repo.get!(User, other_id(c, user.id))
    Ledger.append_change(peer, repayment_envelope(peer, value))
    repayment_envelope(user, value)
  end

  defp create(user, id, op) do
    if existing = Repo.get(SharedExpense, id) do
      if allowed?(user, existing),
        do: Repo.rollback({:conflict, expense_envelope(user, existing)}),
        else: Repo.rollback(:not_found)
    end

    source = Repo.get_by(Expense, id: id, user_id: user.id)
    if is_nil(source) || source.deleted_at, do: Repo.rollback(:not_found)

    if op["payload"]["sourceRevision"] != source.revision,
      do: Repo.rollback({:validation, "The expense changed. Sync it before sharing."})

    if op["expectedRevision"] != 0 || op["action"] != "upsert",
      do: Repo.rollback(:invalid_operation)

    p = op["payload"]
    {recipient, email} = recipient!(user, p)
    connection = recipient && find_connection(user.id, recipient.id)
    split = split!(p["creatorSplit"])
    payer = bool!(p["paidByCreator"])

    e =
      Repo.insert!(%SharedExpense{
        id: id,
        creator_id: user.id,
        recipient_id: if(connection, do: recipient.id),
        recipient_email: email,
        connection_id: connection && connection.id,
        status: if(connection, do: "accepted", else: "pending"),
        amount: source.amount,
        description: source.description,
        expense_date: source.expense_date,
        client_created_at: source.client_created_at,
        creator_split: split,
        paid_by_creator: payer
      })

    Repo.insert!(%Assignment{expense_id: id, user_id: user.id, category_id: source.category_id})

    # The shared envelope transfers the source atomically on each client; no split feed-page transfer.
    source
    |> change(deleted_at: DateTime.utc_now(), revision: source.revision + 1)
    |> Repo.update!()

    add_history(e, user, "shared", common(e))

    if connection do
      ensure_assignment(recipient, e)
      Ledger.append_change(recipient, expense_envelope(recipient, e))
    else
      Repo.insert!(%MailJob{expense_id: id, available_at: DateTime.utc_now()})
      if recipient, do: emit_invitation(recipient, e)
    end

    expense_envelope(user, e)
  end

  defp accept(user, id, op) do
    e = Repo.get(SharedExpense, id) || Repo.rollback(:not_found)
    verified = Repo.get_by(VerifiedEmail, user_id: user.id)

    unless verified && verified.address == e.recipient_email && e.creator_id != user.id,
      do: Repo.rollback(:not_found)

    if e.deleted_at || e.status != "pending", do: Repo.rollback(:not_found)
    unless op["action"] == "upsert", do: Repo.rollback(:invalid_operation)
    # An invitation shows no financial fields. Acceptance always takes the current common record.
    if op["expectedRevision"] != e.revision,
      do: Repo.rollback({:validation, "The invitation changed. Refresh before accepting."})

    c = find_connection(e.creator_id, user.id) || new_connection(e.creator_id, user.id)

    updated =
      e
      |> change(
        recipient_id: user.id,
        connection_id: c.id,
        status: "accepted",
        revision: e.revision + 1
      )
      |> Repo.update!()

    ensure_assignment(user, updated)
    add_history(updated, user, "accepted", %{})
    creator = Repo.get!(User, e.creator_id)
    Ledger.append_change(creator, expense_envelope(creator, updated))
    updated |> invitation_envelope() |> then(&Ledger.append_change(user, &1))
    expense_envelope(user, updated)
  end

  defp edit(user, id, op) do
    e = expense!(user, id)

    if op["expectedRevision"] != e.revision || e.deleted_at,
      do: Repo.rollback({:conflict, expense_envelope(user, e)})

    p = op["payload"]

    attrs =
      if op["action"] == "delete" do
        %{deleted_at: DateTime.utc_now()}
      else
        unless money?(p["amount"]) && is_binary(p["description"]) &&
                 String.length(p["description"]) <= 500,
               do: invalid!("Enter a valid shared amount and description.")

        %{
          amount: p["amount"],
          description: String.trim(p["description"]),
          expense_date: day!(p["day"]),
          paid_by_creator: bool!(p["paidByCreator"]),
          creator_split: split!(p["creatorSplit"])
        }
      end

    saved = e |> change(Map.put(attrs, :revision, e.revision + 1)) |> Repo.update!()
    changes = common(saved) |> Enum.filter(fn {k, v} -> common(e)[k] != v end) |> Map.new()
    add_history(saved, user, if(op["action"] == "delete", do: "deleted", else: "edited"), changes)

    if e.status == "accepted" do
      peer = Repo.get!(User, if(e.creator_id == user.id, do: e.recipient_id, else: e.creator_id))
      Ledger.append_change(peer, expense_envelope(peer, saved))
    else
      if recipient = verified_user(e.recipient_email), do: emit_invitation(recipient, saved)
    end

    expense_envelope(user, saved)
  end

  def email_verified(user, address) do
    for e <-
          Repo.all(
            from e in SharedExpense,
              where:
                e.recipient_email == ^address and e.status == "pending" and is_nil(e.deleted_at)
          ),
        e.creator_id != user.id,
        do: emit_invitation(user, e)

    :ok
  end

  defp emit_invitation(user, e) do
    old = Repo.get_by(InvitationReceipt, expense_id: e.id, user_id: user.id)

    if is_nil(old) || old.revision < e.revision do
      if old,
        do: old |> change(revision: e.revision) |> Repo.update!(),
        else:
          Repo.insert!(%InvitationReceipt{
            expense_id: e.id,
            user_id: user.id,
            revision: e.revision
          })

      Ledger.append_change(user, invitation_envelope(e))
    end
  end

  def expense_envelope(user, e) do
    unless allowed?(user, e), do: Repo.rollback(:not_found)
    assignment = Repo.get_by!(Assignment, expense_id: e.id, user_id: user.id)
    category = Repo.get!(Category, assignment.category_id)

    annual =
      Repo.get_by(YearBudget,
        user_id: user.id,
        category_id: category.id,
        year: e.expense_date.year
      )

    history =
      Repo.all(
        from h in History,
          where: h.expense_id == ^e.id,
          order_by: [asc: h.inserted_at, asc: h.revision]
      )

    payload =
      Map.merge(common(e), %{
        "id" => e.id,
        "viewerID" => user.id,
        "creatorID" => e.creator_id,
        "recipientID" => e.recipient_id,
        "creatorName" => Repo.get!(User, e.creator_id).username,
        "recipientName" => if(e.recipient_id, do: Repo.get!(User, e.recipient_id).username),
        "recipientEmail" => e.recipient_email,
        "status" => e.status,
        "deleted" => e.deleted_at != nil,
        "createdAt" => iso(e.client_created_at),
        "categoryID" => assignment.category_id,
        "assignmentRevision" => assignment.revision,
        "revision" => e.revision,
        "connection" =>
          if(e.connection_id, do: connection_value(user, Repo.get!(Connection, e.connection_id))),
        "bootstrapRecords" =>
          Enum.map(Enum.reject([category, annual], &is_nil/1), &Ledger.envelope/1),
        "history" =>
          Enum.map(history, fn h ->
            %{
              "id" => h.id,
              "actorName" => Repo.get!(User, h.actor_id).username,
              "action" => h.action,
              "at" => iso(h.inserted_at),
              "changes" => h.changes
            }
          end)
      })

    record("shared_expense", e.id, e.revision, e.deleted_at != nil, payload)
  end

  def assignment_envelope(a),
    do:
      record("shared_assignment", a.expense_id, a.revision, false, %{
        "id" => a.expense_id,
        "categoryID" => a.category_id
      })

  defp invitation_envelope(e),
    do:
      record(
        "sharing_invitation",
        e.id,
        e.revision,
        e.status != "pending" || e.deleted_at != nil,
        %{
          "id" => e.id,
          "senderName" => Repo.get!(User, e.creator_id).username,
          "email" => e.recipient_email,
          "createdAt" => iso(e.client_created_at)
        }
      )

  def repayment_envelope(user, r) do
    c = connection!(user, r.connection_id)

    record("repayment", r.id, r.revision, false, %{
      "id" => r.id,
      "viewerID" => user.id,
      "connectionID" => c.id,
      "payerID" => r.payer_id,
      "recipientID" => r.recipient_id,
      "amount" => r.amount,
      "day" => day_value(r.repayment_date),
      "createdAt" => iso(r.client_created_at),
      "actorName" => Repo.get!(User, r.actor_id).username,
      "connection" => connection_value(user, c)
    })
  end

  defp record(kind, id, revision, deleted, payload),
    do: %{
      "entity" => kind,
      "entityID" => id,
      "revision" => revision,
      "deleted" => deleted,
      "payload" => payload
    }

  defp common(e),
    do: %{
      "amount" => e.amount,
      "description" => e.description,
      "day" => day_value(e.expense_date),
      "paidByCreator" => e.paid_by_creator,
      "creatorSplit" => e.creator_split
    }

  defp add_history(e, user, action, changes),
    do:
      Repo.insert!(%History{
        expense_id: e.id,
        actor_id: user.id,
        revision: e.revision,
        action: action,
        changes: changes
      })

  def snapshot(user) do
    email = Repo.get_by(VerifiedEmail, user_id: user.id)

    expenses =
      Repo.all(
        from e in SharedExpense, where: e.creator_id == ^user.id or e.recipient_id == ^user.id
      )

    invitations =
      if email,
        do:
          Repo.all(
            from e in SharedExpense,
              where:
                e.recipient_email == ^email.address and e.status == "pending" and
                  is_nil(e.deleted_at) and e.creator_id != ^user.id
          ),
        else: []

    connections =
      Repo.all(from c in Connection, where: c.user_low == ^user.id or c.user_high == ^user.id)

    ids = Enum.map(connections, & &1.id)
    repayments = Repo.all(from r in Repayment, where: r.connection_id in ^ids)

    %{
      expenses: Enum.map(expenses, &expense_envelope(user, &1)),
      invitations: Enum.map(invitations, &invitation_envelope/1),
      connections: Enum.map(connections, &connection_value(user, &1)),
      repayments: Enum.map(repayments, &repayment_envelope(user, &1))
    }
  end

  def projected_expenses(user) do
    Repo.all(
      from e in SharedExpense,
        where: (e.creator_id == ^user.id or e.recipient_id == ^user.id) and is_nil(e.deleted_at)
    )
    |> Enum.map(fn e ->
      assignment = Repo.get_by!(Assignment, expense_id: e.id, user_id: user.id)
      share = amounts(user, e)["personalShare"]

      %Expense{
        id: e.id,
        user_id: user.id,
        category_id: assignment.category_id,
        amount: e.amount,
        personal_share: share,
        description: e.description,
        expense_date: e.expense_date,
        client_created_at: e.client_created_at,
        inserted_at: e.inserted_at,
        revision: e.revision,
        currency: "EUR"
      }
    end)
  end

  def balance(user, connection_id) do
    expenses =
      Repo.all(
        from e in SharedExpense,
          where:
            e.connection_id == ^connection_id and e.status == "accepted" and is_nil(e.deleted_at)
      )
      |> Enum.map(&amounts(user, &1))

    repayments =
      Repo.all(from r in Repayment, where: r.connection_id == ^connection_id)
      |> Enum.map(&%{"amount" => &1.amount, "paidByUser" => &1.payer_id == user.id})

    SharedMath.summarize(expenses, repayments)["balance"]
  end

  defp amounts(user, e) do
    own_creator = user.id == e.creator_id
    split = if own_creator, do: e.creator_split, else: inverse(e.creator_split)
    SharedMath.calculate(e.amount, split, e.paid_by_creator == own_creator)
  end

  defp inverse("all"), do: "none"
  defp inverse("none"), do: "all"
  defp inverse("half"), do: "half"

  def listeners(user, kind, id) when kind in ["shared_expense", "repayment"] do
    case kind do
      "shared_expense" ->
        e = Repo.get!(SharedExpense, id)

        peer =
          if e.recipient_id,
            do: e.recipient_id,
            else: (verified_user(e.recipient_email) || %{}) |> Map.get(:id)

        Enum.reject([e.creator_id, peer], &is_nil/1)

      "repayment" ->
        c = Repo.get!(Repayment, id) |> then(&Repo.get!(Connection, &1.connection_id))
        [c.user_low, c.user_high]
    end
    |> Enum.uniq()
    |> then(&Enum.uniq([user.id | &1]))
  end

  def listeners(user, _, _), do: [user.id]

  defp ensure_assignment(user, e) do
    if is_nil(Repo.get_by(Assignment, expense_id: e.id, user_id: user.id)) do
      category =
        Repo.get_by(Category, user_id: user.id, name_key: "uncategorized") ||
          Repo.insert!(%Category{
            user_id: user.id,
            name: "Uncategorized",
            name_key: "uncategorized"
          })

      unless Repo.get_by(YearBudget,
               user_id: user.id,
               category_id: category.id,
               year: e.expense_date.year
             ),
             do:
               Repo.insert!(%YearBudget{
                 user_id: user.id,
                 category_id: category.id,
                 year: e.expense_date.year,
                 amount: 0
               })

      Repo.insert!(%Assignment{expense_id: e.id, user_id: user.id, category_id: category.id})
    end
  end

  defp recipient!(user, p) do
    if id = p["recipientID"] do
      id = uuid!(id)
      unless find_connection(user.id, id), do: Repo.rollback(:not_found)
      value = Repo.get!(User, id)
      verified = Repo.get_by(VerifiedEmail, user_id: id)
      {value, verified && verified.address}
    else
      case EmailVerification.normalize(p["recipientEmail"]) do
        {:ok, email} ->
          recipient = verified_user(email)
          if recipient && recipient.id == user.id, do: invalid!("Choose another person.")
          {recipient, email}

        _ ->
          invalid!("Enter the other person's email address.")
      end
    end
  end

  defp verified_user(nil), do: nil

  defp verified_user(email),
    do:
      Repo.one(
        from v in VerifiedEmail,
          join: u in User,
          on: u.id == v.user_id,
          where: v.address == ^email,
          select: u
      )

  defp allowed?(user, e),
    do: e.creator_id == user.id || (e.status == "accepted" && e.recipient_id == user.id)

  defp expense!(user, id) do
    e = Repo.get(SharedExpense, id) || Repo.rollback(:not_found)
    unless allowed?(user, e), do: Repo.rollback(:not_found)
    e
  end

  defp connection!(user, id) do
    c = Repo.get(Connection, uuid!(id)) || Repo.rollback(:not_found)
    unless participant?(user, c), do: Repo.rollback(:not_found)
    c
  end

  defp participant?(user, c), do: user.id in [c.user_low, c.user_high]
  defp other_id(c, id), do: if(c.user_low == id, do: c.user_high, else: c.user_low)

  defp find_connection(a, b) do
    [low, high] = Enum.sort([a, b])
    Repo.get_by(Connection, user_low: low, user_high: high)
  end

  defp new_connection(a, b) do
    [low, high] = Enum.sort([a, b])
    Repo.insert!(%Connection{user_low: low, user_high: high})
  end

  defp connection_value(user, c) do
    peer = Repo.get!(User, other_id(c, user.id))
    %{"id" => c.id, "otherID" => peer.id, "otherName" => peer.username}
  end

  defp owned_category!(user, id) do
    id = uuid!(id)
    if Repo.get_by(Category, id: id, user_id: user.id), do: id, else: Repo.rollback(:not_found)
  end

  defp uuid!(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> id
      _ -> Repo.rollback(:not_found)
    end
  end

  defp money?(value), do: is_integer(value) && value in 1..@maximum
  defp bool!(v) when is_boolean(v), do: v
  defp bool!(_), do: Repo.rollback(:invalid_operation)
  defp split!(v) when v in ["all", "half", "none"], do: v
  defp split!(_), do: Repo.rollback(:invalid_operation)
  defp invalid!(message), do: Repo.rollback({:validation, message})

  defp day!(%{"year" => y, "month" => m, "day" => d})
       when is_integer(y) and is_integer(m) and is_integer(d) and y in 1900..9999 do
    case Date.new(y, m, d) do
      {:ok, date} -> date
      _ -> Repo.rollback(:invalid_operation)
    end
  end

  defp day!(_), do: Repo.rollback(:invalid_operation)
  defp day_value(date), do: %{"year" => date.year, "month" => date.month, "day" => date.day}

  defp created!(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date, _} -> DateTime.truncate(date, :second)
      _ -> Repo.rollback(:invalid_operation)
    end
  end

  defp created!(_), do: Repo.rollback(:invalid_operation)
  defp iso(date), do: date |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
