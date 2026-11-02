defmodule MoneyTrackWeb.SharedLive do
  use MoneyTrackWeb, :live_view
  alias MoneyTrack.{Ledger, Sharing}
  @impl true
  def mount(_, _, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(MoneyTrack.PubSub, "ledger:#{socket.assigns.current_user.id}")

    {:ok,
     socket
     |> assign(
       person: nil,
       error: nil,
       conflict: nil,
       editing: nil,
       edit_form: nil,
       share_form:
         to_form(
           %{
             "id" => "",
             "recipientEmail" => "",
             "recipientID" => "",
             "creatorSplit" => "half",
             "paidByCreator" => "true"
           },
           as: :share
         ),
       repayment_form: nil
     )
     |> reload()}
  end

  @impl true
  def handle_params(params, _, socket) do
    socket = assign(socket, person: params["person"])

    socket =
      if id = params["expense"] do
        if e = Enum.find(socket.assigns.sharing.expenses, &(&1["entityID"] == id)) do
          start_edit(socket, e)
        else
          case Enum.find(socket.assigns.personal.expenses, &(&1.id == id)) do
            nil ->
              socket

            e ->
              assign(socket,
                share_form:
                  to_form(Map.put(socket.assigns.share_form.params, "id", e.id), as: :share)
              )
          end
        end
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:ledger_changed, socket), do: {:noreply, reload(socket)}
  @impl true
  def handle_event("share", %{"share" => p}, socket) do
    source = Enum.find(socket.assigns.personal.expenses, &(&1.id == p["id"]))
    socket = assign(socket, share_form: to_form(p, as: :share))

    if source do
      payload = %{
        "id" => source.id,
        "command" => "share",
        "sourceRevision" => source.revision,
        "creatorSplit" => p["creatorSplit"],
        "paidByCreator" => p["paidByCreator"] == "true"
      }

      payload =
        if p["recipientID"] in [nil, ""],
          do: Map.put(payload, "recipientEmail", p["recipientEmail"]),
          else: Map.put(payload, "recipientID", p["recipientID"])

      {:noreply, save(socket, op("shared_expense", payload, 0))}
    else
      {:noreply, assign(socket, error: "Choose a personal expense to share.")}
    end
  end

  def handle_event("accept", %{"id" => id, "revision" => revision}, socket),
    do:
      {:noreply,
       save(
         socket,
         op("shared_expense", %{"id" => id, "command" => "accept"}, int_value(revision))
       )}

  def handle_event("edit", %{"id" => id}, socket) do
    e = Enum.find(socket.assigns.sharing.expenses, &(&1["entityID"] == id))
    {:noreply, if(e, do: start_edit(socket, e), else: socket)}
  end

  def handle_event("edit_change", %{"shared" => p}, socket),
    do: {:noreply, assign(socket, edit_form: to_form(p, as: :shared))}

  def handle_event("save", %{"shared" => p}, socket) do
    socket = assign(socket, edit_form: to_form(p, as: :shared))

    with {:ok, amount} <- amount(p["amount"]), {:ok, date} <- Date.from_iso8601(p["day"] || "") do
      payload = %{
        "id" => p["id"],
        "amount" => amount,
        "description" => p["description"],
        "day" => day(date),
        "paidByCreator" => p["paidByCreator"] == "true",
        "creatorSplit" => p["creatorSplit"]
      }

      {:noreply, save(socket, op("shared_expense", payload, int_value(p["revision"])))}
    else
      _ -> {:noreply, assign(socket, error: "Enter a valid amount and date.")}
    end
  end

  def handle_event("category", %{"assignment" => p}, socket) do
    {:noreply,
     save(
       socket,
       op("shared_assignment", Map.take(p, ~w(id categoryID)), int_value(p["revision"]))
     )}
  end

  def handle_event("delete", %{"id" => id, "revision" => revision}, socket),
    do:
      {:noreply, save(socket, op("shared_expense", %{"id" => id}, int_value(revision), "delete"))}

  def handle_event("settle", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.sharing.connections, &(&1["id"] == id)) do
      balance = Sharing.balance(socket.assigns.current_user, id)

      form = %{
        "id" => Ecto.UUID.generate(),
        "connectionID" => id,
        "balance" => to_string(balance),
        "amount" => input_amount(abs(balance)),
        "day" => Date.to_iso8601(Date.utc_today()),
        "createdAt" => DateTime.to_iso8601(DateTime.utc_now())
      }

      {:noreply, assign(socket, repayment_form: to_form(form, as: :repayment), error: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("repay", %{"repayment" => p}, socket) do
    socket = assign(socket, repayment_form: to_form(p, as: :repayment))

    with {:ok, amount} <- amount(p["amount"]),
         {:ok, date} <- Date.from_iso8601(p["day"] || ""),
         {balance, ""} <- Integer.parse(p["balance"] || ""),
         connection when not is_nil(connection) <-
           Enum.find(socket.assigns.sharing.connections, &(&1["id"] == p["connectionID"])) do
      payload = %{
        "id" => p["id"],
        "connectionID" => connection["id"],
        "payerID" =>
          if(balance < 0, do: socket.assigns.current_user.id, else: connection["otherID"]),
        "balanceAtConfirmation" => balance,
        "amount" => amount,
        "day" => day(date),
        "createdAt" => p["createdAt"]
      }

      {:noreply, save(socket, op("repayment", payload, 0))}
    else
      _ -> {:noreply, assign(socket, error: "Enter a valid repayment amount and date.")}
    end
  end

  def handle_event("cancel", _, socket),
    do:
      {:noreply,
       assign(socket,
         editing: nil,
         edit_form: nil,
         repayment_form: nil,
         conflict: nil,
         error: nil
       )}

  def handle_event("use_server", _, socket) do
    {:noreply,
     socket
     |> assign(conflict: nil, error: nil)
     |> reload()
     |> then(fn s ->
       if s.assigns.editing,
         do:
           start_edit(
             s,
             Enum.find(s.assigns.sharing.expenses, &(&1["entityID"] == s.assigns.editing))
           ),
         else: s
     end)}
  end

  def handle_event("keep_local", _, socket) do
    case socket.assigns.conflict do
      %{operation: operation, current: %{"deleted" => false} = current} ->
        operation =
          operation
          |> Map.put("operationID", Ecto.UUID.generate())
          |> Map.put("expectedRevision", current["revision"])

        {:noreply, save(socket, operation)}

      _ ->
        {:noreply, socket}
    end
  end

  defp save(socket, operation) do
    case Ledger.apply_operation(socket.assigns.current_user, operation) do
      {:ok, _} ->
        socket
        |> assign(error: nil, conflict: nil, editing: nil, edit_form: nil, repayment_form: nil)
        |> reload()

      {:error, {:conflict, current}} ->
        socket
        |> assign(
          conflict: %{operation: operation, current: current},
          error: "This shared item changed. Review before replacing it."
        )
        |> reload()

      {:error, {:validation, message}} ->
        socket |> assign(error: message) |> reload()

      _ ->
        socket |> assign(error: "This item is unavailable or its fields need review.") |> reload()
    end
  end

  defp reload(socket),
    do:
      assign(socket,
        sharing: Sharing.snapshot(socket.assigns.current_user),
        personal: Ledger.snapshot(socket.assigns.current_user)
      )

  defp start_edit(socket, nil), do: assign(socket, editing: nil, edit_form: nil)

  defp start_edit(socket, e) do
    p = e["payload"]

    form = %{
      "id" => e["entityID"],
      "revision" => to_string(e["revision"]),
      "amount" => input_amount(p["amount"]),
      "description" => p["description"],
      "day" => iso_day(p["day"]),
      "paidByCreator" => to_string(p["paidByCreator"]),
      "creatorSplit" => p["creatorSplit"]
    }

    assign(socket, editing: e["entityID"], edit_form: to_form(form, as: :shared))
  end

  defp op(kind, p, revision, action \\ "upsert"),
    do: %{
      "operationID" => Ecto.UUID.generate(),
      "entity" => kind,
      "entityID" => p["id"],
      "payload" => p,
      "expectedRevision" => revision,
      "action" => action
    }

  defp int_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> 0
    end
  end

  defp int_value(_), do: 0

  defp amount(value) when is_binary(value) do
    value = value |> String.trim() |> String.replace(",", ".")

    if byte_size(value) <= 16 && Regex.match?(~r/\A[0-9]+(?:\.[0-9]{1,2})?\z/, value) do
      [whole | rest] = String.split(value, ".")

      fraction =
        case rest do
          [] -> 0
          [v] -> v |> String.pad_trailing(2, "0") |> String.to_integer()
        end

      cents = String.to_integer(whole) * 100 + fraction
      if cents in 1..99_999_999_999, do: {:ok, cents}, else: :error
    else
      :error
    end
  end

  defp amount(_), do: :error
  defp day(d), do: %{"year" => d.year, "month" => d.month, "day" => d.day}

  defp iso_day(d),
    do:
      "#{d["year"]}-#{String.pad_leading(to_string(d["month"]), 2, "0")}-#{String.pad_leading(to_string(d["day"]), 2, "0")}"

  defp input_amount(n), do: "#{div(n, 100)}.#{String.pad_leading(to_string(rem(n, 100)), 2, "0")}"
  defp money(n), do: "#{if n < 0, do: "−", else: ""}€#{input_amount(abs(n))}"
  defp balance_label(0), do: "Settled up"
  defp balance_label(n), do: "#{if n > 0, do: "Owes you", else: "You owe"} #{money(abs(n))}"
  defp color(n) when n > 0, do: "text-green-700 dark:text-green-300"
  defp color(n) when n < 0, do: "text-red-700 dark:text-red-300"
  defp color(_), do: "text-base-content"

  defp deletion_message(e, balances) do
    base =
      "Delete this expense? Its spending and obligation are removed; recorded repayments remain."

    p = e["payload"]

    if c = p["connection"] do
      creator = p["viewerID"] == p["creatorID"]

      split = if creator, do: p["creatorSplit"], else: inverse_split(p["creatorSplit"])

      delta =
        MoneyTrack.SharedMath.calculate(p["amount"], split, p["paidByCreator"] == creator)[
          "balance"
        ]

      base <> " After deletion: " <> balance_label(balances[c["id"]] - delta) <> "."
    else
      base <> " The pending invitation will no longer be available."
    end
  end

  defp inverse_split("all"), do: "none"
  defp inverse_split("none"), do: "all"
  defp inverse_split("half"), do: "half"

  defp change_text(changes, p) do
    changes
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map_join(" · ", fn {key, value} ->
      case key do
        "amount" ->
          "Amount: #{money(value)}"

        "description" ->
          "Description: #{value}"

        "day" ->
          "Date: #{iso_day(value)}"

        "paidByCreator" ->
          "Paid by: #{if value, do: p["creatorName"], else: p["recipientName"] || p["recipientEmail"] || "Other person"}"

        "creatorSplit" ->
          "#{p["creatorName"]}'s share: #{String.capitalize(value)}"
      end
    end)
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        balances:
          Map.new(
            assigns.sharing.connections,
            &{&1["id"], Sharing.balance(assigns.current_user, &1["id"])}
          ),
        personal_options:
          Enum.reject(assigns.personal.expenses, fn e ->
            Enum.any?(assigns.sharing.expenses, &(&1["entityID"] == e.id))
          end)
          |> Enum.map(
            &{if(&1.description == "", do: money(&1.amount), else: &1.description), &1.id}
          )
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={%{user: @current_user}}>
      <.link navigate={~p"/"} class="link">Budget</.link>
      <h1 class="text-2xl font-semibold">Shared</h1>
      <p :if={@error} id="sharing-error" role="alert" class="text-error">{@error}</p>
      <section :if={@conflict} id="sharing-conflict" class="card border border-warning p-4">
        <p>
          Server version: {Jason.encode!(
            @conflict.current["payload"]
            |> Map.take(~w(amount description creatorSplit paidByCreator))
          )}
        </p>
        <button phx-click="use_server" class="btn">Use Server Version</button>
        <button :if={!@conflict.current["deleted"]} phx-click="keep_local" class="btn">Keep My Changes</button>
      </section>
      <section :if={@sharing.invitations != []} class="space-y-3">
        <h2 class="text-xl font-semibold">Invitations</h2>
        <div
          :for={e <- @sharing.invitations}
          id={"invitation-#{e["entityID"]}"}
          class="card border p-4"
        >
          <p>
            {e["payload"]["senderName"]} invited you. Your share starts in your private Uncategorized category.
          </p>
          <button
            phx-click="accept"
            phx-value-id={e["entityID"]}
            phx-value-revision={e["revision"]}
            class="btn"
            phx-disable-with="Accepting…"
          >Accept Invitation</button>
        </div>
      </section>
      <section class="space-y-3">
        <h2 class="text-xl font-semibold">People</h2>
        <div
          :for={c <- @sharing.connections}
          id={"person-#{c["id"]}"}
          class="card border p-4 space-y-2"
        >
          <.link patch={~p"/shared?#{%{person: c["id"]}}"}>{c["otherName"]}</.link>
          <p class={color(@balances[c["id"]])}>{balance_label(@balances[c["id"]])}</p>
          <button
            phx-click="settle"
            phx-value-id={c["id"]}
            disabled={@balances[c["id"]] == 0}
            class="btn"
          >Settle Up</button>
        </div>
      </section>
      <.form
        :if={@repayment_form}
        for={@repayment_form}
        id="repayment-form"
        phx-submit="repay"
        class="card border p-4"
      >
        <h2 class="text-xl font-semibold">Settle Up</h2>
        <p>
          {if int_value(@repayment_form.params["balance"]) < 0,
            do: "You paid the other person",
            else: "The other person paid you"}. Only records a payment made outside MoneyTrack. Budgets stay unchanged.
        </p>
        <.input
          :for={key <- [:id, :connectionID, :balance, :createdAt]}
          field={@repayment_form[key]}
          type="hidden"
        />
        <.currency_input field={@repayment_form[:amount]} label="Amount (€)" required />
        <.input
          field={@repayment_form[:day]}
          type="date"
          phx-hook="LocalExpenseDay"
          data-entry-id={@repayment_form[:id].value}
          data-new="true"
          label="Date"
          required
        />
        <.button phx-disable-with="Recording…">Record Repayment</.button>
        <button type="button" phx-click="cancel" class="btn">Cancel</button>
      </.form>
      <section class="card border p-4">
        <h2 class="text-xl font-semibold">Share a Saved Expense</h2>
        <.form for={@share_form} id="share-form" phx-submit="share">
          <.input
            field={@share_form[:id]}
            type="select"
            label="Expense"
            prompt="Choose a personal expense"
            options={@personal_options}
            required
          />
          <.input
            field={@share_form[:recipientID]}
            type="select"
            label="Existing connection (optional)"
            prompt="Invite by email"
            options={Enum.map(@sharing.connections, &{&1["otherName"], &1["otherID"]})}
          />
          <.input field={@share_form[:recipientEmail]} type="email" label="Recipient email" />
          <.input
            field={@share_form[:paidByCreator]}
            type="select"
            label="Paid by"
            options={[{"You", "true"}, {"Other person", "false"}]}
          />
          <.input
            field={@share_form[:creatorSplit]}
            type="select"
            label="Your share"
            options={[{"All", "all"}, {"Half", "half"}, {"None", "none"}]}
          />
          <p class="text-sm">Your proposed share counts in the original expense month immediately.</p>
          <.button phx-disable-with="Sharing…">Share Expense</.button>
        </.form>
      </section>
      <.form
        :if={@edit_form}
        for={@edit_form}
        id="shared-edit-form"
        phx-submit="save"
        phx-change="edit_change"
        class="card border p-4"
      >
        <h2 class="text-xl font-semibold">Edit Shared Expense</h2>
        <.input :for={key <- [:id, :revision]} field={@edit_form[key]} type="hidden" />
        <.currency_input field={@edit_form[:amount]} label="Amount (€)" required />
        <.input field={@edit_form[:description]} label="Description" maxlength="500" />
        <.input field={@edit_form[:day]} label="Date" type="date" required />
        <.input
          field={@edit_form[:paidByCreator]}
          type="select"
          label="Paid by"
          options={[{"Original creator", "true"}, {"Other participant", "false"}]}
        />
        <.input
          field={@edit_form[:creatorSplit]}
          type="select"
          label="Original creator's share"
          options={[{"All", "all"}, {"Half", "half"}, {"None", "none"}]}
        />
        <.button>Save Shared Changes</.button>
        <button type="button" phx-click="cancel" class="btn">Cancel</button>
      </.form>
      <section
        :for={e <- @sharing.expenses}
        :if={is_nil(@person) || e["payload"]["connection"]["id"] == @person}
        id={"shared-#{e["entityID"]}"}
        class="card border p-4 space-y-2"
      >
        <h2>{e["payload"]["description"]}</h2>
        <p>
          {money(e["payload"]["amount"])} total · {iso_day(e["payload"]["day"])} · {if e["deleted"],
            do: "Deleted",
            else: e["payload"]["status"]}
        </p>
        <button :if={!e["deleted"]} phx-click="edit" phx-value-id={e["entityID"]} class="btn">Edit Shared Expense</button>
        <button
          :if={!e["deleted"]}
          phx-click="delete"
          phx-value-id={e["entityID"]}
          phx-value-revision={e["revision"]}
          class="btn"
          data-confirm={deletion_message(e, @balances)}
        >Delete Shared Expense</button>
        <.form
          :if={!e["deleted"]}
          for={
            to_form(
              %{
                "id" => e["entityID"],
                "revision" => to_string(e["payload"]["assignmentRevision"]),
                "categoryID" => e["payload"]["categoryID"]
              },
              as: :assignment
            )
          }
          id={"assignment-#{e["entityID"]}"}
          phx-submit="category"
        >
          <.input type="hidden" name="assignment[id]" value={e["entityID"]} />
          <.input
            type="hidden"
            name="assignment[revision]"
            value={e["payload"]["assignmentRevision"]}
          />
          <.input
            type="select"
            name="assignment[categoryID]"
            value={e["payload"]["categoryID"]}
            label="Your private category"
            options={Enum.map(@personal.categories, &{&1.name, &1.id})}
          />
          <.button>Save Your Category</.button>
        </.form>
        <details>
          <summary>Shared History</summary>
          <p :for={h <- e["payload"]["history"]}>
            {h["actorName"]} · {h["action"]} · {h["at"]} · {change_text(h["changes"], e["payload"])}
          </p>
        </details>
      </section>
      <section :if={@sharing.repayments != []} class="space-y-3">
        <h2 class="text-xl font-semibold">Repayments</h2>
        <p
          :for={r <- @sharing.repayments}
          :if={is_nil(@person) || r["payload"]["connectionID"] == @person}
        >
          {if r["payload"]["payerID"] == @current_user.id,
            do: "You paid #{r["payload"]["connection"]["otherName"]}",
            else: "#{r["payload"]["connection"]["otherName"]} paid you"} {money(
            r["payload"]["amount"]
          )} · {iso_day(r["payload"]["day"])} · Recorded by {r["payload"]["actorName"]}
        </p>
      </section>
    </Layouts.app>
    """
  end
end
