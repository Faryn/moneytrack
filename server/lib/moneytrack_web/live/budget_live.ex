defmodule MoneyTrackWeb.BudgetLive do
  use MoneyTrackWeb, :live_view
  alias MoneyTrack.Ledger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(MoneyTrack.PubSub, "ledger:#{socket.assigns.current_user.id}")

    {:ok,
     socket
     |> assign(
       page_title: gettext("Budget"),
       month: Date.beginning_of_month(Date.utc_today()),
       conflict: nil
     )
     |> reload()
     |> new_expense()
     |> new_budget()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    month =
      case Date.from_iso8601(
             (params["month"] || Calendar.strftime(Date.utc_today(), "%Y-%m")) <> "-01"
           ) do
        {:ok, date} when date.year in 1900..9999 -> date
        _ -> socket.assigns.month
      end

    blank =
      Enum.all?(~w(categoryID name amount), &(socket.assigns.budget_form.params[&1] in [nil, ""]))

    changed_year = month.year != socket.assigns.month.year
    socket = assign(socket, :month, month)
    socket = if changed_year && blank, do: new_budget(socket), else: socket
    {:noreply, socket}
  end

  @impl true
  def handle_info(:ledger_changed, socket), do: {:noreply, reload(socket)}

  @impl true
  def handle_event("month", %{"month" => month}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/?#{%{month: month}}")}

  def handle_event("edit_expense", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.ledger.expenses, &(&1.id == id)) &&
         MoneyTrack.Repo.get(MoneyTrack.Sharing.SharedExpense, id) do
      {:noreply, push_navigate(socket, to: ~p"/shared?#{%{expense: id}}")}
    else
      case Enum.find(socket.assigns.ledger.expenses, &(&1.id == id)) do
        nil ->
          {:noreply, put_flash(socket, :error, gettext("That expense is no longer available."))}

        expense ->
          payload = Ledger.envelope(expense)["payload"]

          {:noreply,
           assign(
             socket,
             :expense_form,
             to_form(
               %{
                 "id" => id,
                 "operationID" => Ecto.UUID.generate(),
                 "revision" => to_string(expense.revision),
                 "amount" =>
                   if(expense.conversion,
                     do: MoneyTrack.Currency.original_input(expense.conversion),
                     else: input_amount(expense.amount)
                   ),
                 "currency" =>
                   if(expense.conversion, do: expense.conversion["originalCurrency"], else: "EUR"),
                 "kind" => expense.kind,
                 "description" => expense.description,
                 "categoryID" => expense.category_id,
                 "day" => Date.to_iso8601(expense.expense_date),
                 "createdAt" => payload["createdAt"]
               },
               as: :expense
             )
           )}
      end
    end
  end

  def handle_event("expense_change", %{"expense" => params}, socket),
    do: {:noreply, assign(socket, :expense_form, to_form(params, as: :expense))}

  def handle_event("cancel_expense", _, socket), do: {:noreply, new_expense(socket)}

  def handle_event("save_expense", %{"expense" => params}, socket) do
    socket = assign(socket, :expense_form, to_form(params, as: :expense))

    old = Enum.find(socket.assigns.ledger.expenses, &(&1.id == params["id"]))

    with {:ok, cents, conversion} <-
           MoneyTrack.Currency.from_input(
             params["amount"],
             params["currency"],
             old && old.conversion
           ),
         {:ok, date} <- Date.from_iso8601(params["day"] || ""),
         {revision, ""} <- Integer.parse(params["revision"] || "") do
      payload = %{
        "id" => params["id"],
        "categoryID" => params["categoryID"],
        "amount" => cents,
        "personalShare" => cents,
        "conversion" => conversion,
        "kind" => params["kind"] || "expense",
        "description" => params["description"] || "",
        "day" => %{"year" => date.year, "month" => date.month, "day" => date.day},
        "createdAt" => params["createdAt"]
      }

      op = operation("expense", payload, revision, params["operationID"])

      {:noreply,
       save_operation(
         socket,
         op,
         if(params["kind"] == "income", do: nil, else: params["shareWith"])
       )}
    else
      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Enter an amount such as 78,50 or 78.50 and a valid date.")
         )}
    end
  end

  def handle_event("delete_expense", %{"id" => id, "revision" => rev}, socket) do
    if Enum.any?(socket.assigns.ledger.expenses, &(&1.id == id)) &&
         MoneyTrack.Repo.get(MoneyTrack.Sharing.SharedExpense, id) do
      {:noreply, push_navigate(socket, to: ~p"/shared?#{%{expense: id}}")}
    else
      case Integer.parse(rev) do
        {revision, ""} ->
          op =
            operation(
              "expense",
              %{"id" => id, "deletedAt" => DateTime.to_iso8601(DateTime.utc_now())},
              revision,
              Ecto.UUID.generate()
            )

          {:noreply, save_operation(socket, Map.put(op, "action", "delete"))}

        _ ->
          {:noreply, socket}
      end
    end
  end

  def handle_event("edit_budget", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.ledger.categories, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      category ->
        budget =
          Enum.find(
            socket.assigns.ledger.budgets,
            &(&1.category_id == id && &1.year == socket.assigns.month.year)
          )

        form = %{
          "categoryID" => id,
          "name" => category.name,
          "id" => if(budget, do: budget.id, else: Ecto.UUID.generate()),
          "operationID" => Ecto.UUID.generate(),
          "revision" => to_string(if(budget, do: budget.revision, else: 0)),
          "year" => to_string(socket.assigns.month.year),
          "amount" => if(budget, do: input_amount(budget.amount), else: "")
        }

        {:noreply, assign(socket, :budget_form, to_form(form, as: :budget))}
    end
  end

  def handle_event("budget_change", %{"budget" => params}, socket) do
    prior = socket.assigns.budget_form.params
    changed = params["categoryID"] != prior["categoryID"] || params["year"] != prior["year"]

    params =
      if changed do
        year =
          case Integer.parse(params["year"] || "") do
            {value, ""} -> value
            _ -> 0
          end

        existing =
          Enum.find(
            socket.assigns.ledger.budgets,
            &(&1.category_id == params["categoryID"] && &1.year == year)
          )

        params
        |> Map.put("id", if(existing, do: existing.id, else: Ecto.UUID.generate()))
        |> Map.put("revision", to_string(if(existing, do: existing.revision, else: 0)))
        |> Map.put(
          "amount",
          if(existing, do: input_amount(existing.amount), else: params["amount"])
        )
        |> Map.put("operationID", Ecto.UUID.generate())
      else
        params
      end

    {:noreply, assign(socket, :budget_form, to_form(params, as: :budget))}
  end

  def handle_event("new_budget", _, socket), do: {:noreply, new_budget(socket)}

  def handle_event("save_budget", %{"budget" => params}, socket) do
    socket = assign(socket, :budget_form, to_form(params, as: :budget))

    with {:ok, cents} <- parse_amount(params["amount"]),
         {year, ""} <- Integer.parse(params["year"] || ""),
         true <- year in 1900..9999,
         {revision, ""} <- Integer.parse(params["revision"] || ""),
         {:ok, category_id} <- ensure_category(socket, params) do
      payload = %{
        "id" => params["id"],
        "categoryID" => category_id,
        "year" => year,
        "amount" => cents
      }

      {:noreply,
       save_operation(socket, operation("year_budget", payload, revision, params["operationID"]))}
    else
      _ ->
        {:noreply,
         reload(socket)
         |> put_flash(
           :error,
           gettext("Check the category, year, and yearly amount. Category names must be unique.")
         )}
    end
  end

  def handle_event("use_server", _, %{assigns: %{conflict: nil}} = socket), do: {:noreply, socket}

  def handle_event("use_server", _, socket) do
    operation = socket.assigns.conflict.operation
    {:noreply, socket |> assign(:conflict, nil) |> reload() |> reset_saved_form(operation)}
  end

  def handle_event("keep_mine", _, %{assigns: %{conflict: nil}} = socket), do: {:noreply, socket}

  def handle_event("keep_mine", _, socket) do
    %{operation: op, current: current} = socket.assigns.conflict

    op =
      op
      |> Map.put("operationID", Ecto.UUID.generate())
      |> Map.put("expectedRevision", current["revision"])

    op =
      if current["deleted"] && op["action"] == "upsert" do
        id = Ecto.UUID.generate()

        op
        |> Map.put("entityID", id)
        |> Map.put("expectedRevision", 0)
        |> put_in(["payload", "id"], id)
      else
        op
      end

    op =
      if !current["deleted"] && current["entityID"] != op["entityID"] do
        op
        |> Map.put("entityID", current["entityID"])
        |> put_in(["payload", "id"], current["entityID"])
      else
        op
      end

    {:noreply, save_operation(socket, op)}
  end

  defp save_operation(socket, operation, share_with \\ nil) do
    result =
      if share_with in [nil, ""],
        do: Ledger.apply_operation(socket.assigns.current_user, operation),
        else: Ledger.create_shared_expense(socket.assigns.current_user, operation, share_with)

    case result do
      {:ok, _} ->
        socket
        |> assign(:conflict, nil)
        |> reload()
        |> reset_saved_form(operation)
        |> put_flash(:info, gettext("Saved"))

      {:error, {:conflict, current}} when not is_nil(current) ->
        assign(socket, :conflict, %{operation: operation, current: current})

      {:error, {:validation, message}} ->
        put_flash(socket, :error, MoneyTrackWeb.Language.message(message))

      {:error, _} ->
        put_flash(
          socket,
          :error,
          gettext("Couldn't save. Your entered values are still in the form.")
        )
    end
  end

  defp reset_saved_form(socket, %{"entity" => "year_budget"}), do: new_budget(socket)

  defp reset_saved_form(socket, %{"entity" => "expense", "action" => "delete", "entityID" => id}) do
    if socket.assigns.expense_form.params["id"] == id, do: new_expense(socket), else: socket
  end

  defp reset_saved_form(socket, _operation), do: new_expense(socket)

  defp ensure_category(_socket, %{"categoryID" => id}) when id != "", do: {:ok, id}

  defp ensure_category(socket, params) do
    id = Ecto.UUID.generate()

    case Ledger.apply_operation(
           socket.assigns.current_user,
           operation(
             "category",
             %{"id" => id, "name" => params["name"] || ""},
             0,
             Ecto.UUID.generate()
           )
         ) do
      {:ok, _} -> {:ok, id}
      error -> error
    end
  end

  defp operation(kind, payload, revision, operation_id),
    do: %{
      "entity" => kind,
      "entityID" => payload["id"],
      "payload" => payload,
      "expectedRevision" => revision,
      "operationID" => operation_id,
      "action" => "upsert"
    }

  defp reload(socket),
    do:
      assign(socket,
        ledger: Ledger.snapshot(socket.assigns.current_user),
        sharing_connections: MoneyTrack.Sharing.snapshot(socket.assigns.current_user).connections
      )

  defp new_expense(socket) do
    assign(
      socket,
      :expense_form,
      to_form(
        %{
          "id" => Ecto.UUID.generate(),
          "operationID" => Ecto.UUID.generate(),
          "revision" => "0",
          "currency" => "EUR",
          "shareWith" => "",
          "kind" => "expense",
          "amount" => "",
          "description" => "",
          "categoryID" => "",
          "day" => Date.to_iso8601(Date.utc_today()),
          "createdAt" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        },
        as: :expense
      )
    )
  end

  defp new_budget(socket),
    do:
      assign(
        socket,
        :budget_form,
        to_form(
          %{
            "categoryID" => "",
            "name" => "",
            "id" => Ecto.UUID.generate(),
            "operationID" => Ecto.UUID.generate(),
            "revision" => "0",
            "year" => to_string(socket.assigns.month.year),
            "amount" => ""
          },
          as: :budget
        )
      )

  defp overview(ledger, month) do
    if plan = Enum.find(ledger.plans, &(&1.year == month.year)) do
      whole = whole_budget(ledger, month, plan)

      Enum.map(ledger.categories, fn c ->
        allocation = Enum.find(plan.allocations["items"], &(&1["categoryID"] == c.id))

        spent =
          ledger.expenses
          |> Enum.filter(
            &(&1.kind != "income" && &1.category_id == c.id && &1.expense_date.year == month.year &&
                &1.expense_date.month == month.month)
          )
          |> Enum.map(& &1.personal_share)
          |> Enum.sum()

        result =
          whole["categories"][c.id] ||
            %{"allocation" => 0, "carryover" => 0, "spent" => spent, "remaining" => 0}

        %{category: c, budget: allocation, result: result}
      end)
    else
      legacy_overview(ledger, month)
    end
  end

  defp whole_budget(ledger, month, plan) do
    expenses =
      Enum.map(ledger.expenses, fn e ->
        %{
          "day" => Date.to_iso8601(e.expense_date),
          "kind" => e.kind,
          "amount" => e.amount,
          "personalShare" => e.personal_share,
          "categoryID" => e.category_id
        }
      end)

    MoneyTrack.Budget.for_plan(
      month.year,
      month.month,
      plan.total,
      plan.allocations["items"],
      plan.free_category_id,
      expenses
    )
  end

  defp legacy_overview(ledger, month) do
    Enum.map(ledger.categories, fn category ->
      budget =
        Enum.find(ledger.budgets, &(&1.category_id == category.id && &1.year == month.year))

      entries =
        for e <- ledger.expenses,
            e.category_id == category.id,
            do: %{
              "day" => Date.to_iso8601(e.expense_date),
              "kind" => e.kind,
              "amount" => e.amount,
              "personalShare" => e.personal_share
            }

      %{
        category: category,
        budget: budget,
        result:
          MoneyTrack.Budget.for_category(
            month.year,
            month.month,
            if(budget, do: budget.amount, else: 0),
            entries
          )
      }
    end)
  end

  defp money(cents), do: MoneyTrackWeb.Language.money(cents)

  defp input_amount(cents),
    do:
      "#{div(cents, 100)}.#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"

  defp month_title(date) do
    months = [
      gettext("January"),
      gettext("February"),
      gettext("March"),
      gettext("April"),
      gettext("May"),
      gettext("June"),
      gettext("July"),
      gettext("August"),
      gettext("September"),
      gettext("October"),
      gettext("November"),
      gettext("December")
    ]

    "#{Enum.at(months, date.month - 1)} #{date.year}"
  end

  defp color(cents) when cents > 0, do: "text-green-700 dark:text-green-300"
  defp color(cents) when cents < 0, do: "text-red-700 dark:text-red-300"
  defp color(_), do: "text-base-content"

  defp parse_amount(value) when is_binary(value) do
    value = value |> String.trim() |> String.replace(",", ".")

    if Regex.match?(~r/\A\d+(\.\d{1,2})?\z/, value) do
      [whole | fraction] = String.split(value, ".")

      fraction =
        case fraction do
          [] -> 0
          [value] -> value |> String.pad_trailing(2, "0") |> String.to_integer()
        end

      amount = String.to_integer(whole) * 100 + fraction
      if amount <= 99_999_999_999, do: {:ok, amount}, else: :error
    else
      :error
    end
  end

  defp parse_amount(_), do: :error

  defp expense_category_options(ledger, day, fallback_year) do
    year =
      case Date.from_iso8601(day || "") do
        {:ok, date} -> date.year
        _ -> fallback_year
      end

    Enum.map(ledger.categories, &{category_label(&1, ledger.plans, ledger.budgets, year), &1.id})
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :overview, overview(assigns.ledger, assigns.month))
    plan = Enum.find(assigns.ledger.plans, &(&1.year == assigns.month.year))
    whole = if plan, do: whole_budget(assigns.ledger, assigns.month, plan)

    remaining =
      if whole,
        do: whole["total"]["remaining"],
        else: Enum.sum(Enum.map(assigns.overview, & &1.result["remaining"]))

    assigns = assign(assigns, plan: plan, whole: whole, total_remaining: remaining)

    ~H"""
    <Layouts.app flash={@flash} current_scope={%{user: @current_user}}>
      <section id="budget-overview" class="space-y-6">
        <h1 id="budget-heading" class="text-3xl font-semibold">{gettext("Your budget")}</h1>
        <form id="month-form" phx-change="month" class="flex items-center gap-3">
          <label for="month">{gettext("Month")}</label>
          <input
            id="month"
            name="month"
            type="month"
            class="input"
            value={Calendar.strftime(@month, "%Y-%m")}
          />
        </form>
        <div
          :if={@plan != nil || Enum.any?(@overview, & &1.budget)}
          class="rounded-box bg-base-200 p-6 space-y-2"
        >
          <p>{gettext("Remaining budget · %{month}", month: month_title(@month))}</p>
          <p :if={@whole} id="assigned-this-month">
            {gettext("%{amount} assigned this month", amount: money(@whole["total"]["allocation"]))}
          </p>
          <p
            id="total-remaining"
            class={[
              "text-4xl font-semibold",
              color(@total_remaining)
            ]}
          >
            {money(@total_remaining)}
          </p>
          <p class="text-sm">
            {gettext(
              "Includes positive and negative carryover since January. Only your share counts."
            )}
          </p>
        </div>
        <p :if={!(@plan != nil || Enum.any?(@overview, & &1.budget))}>
          {gettext("No budget yet. Pick your whole yearly budget, then allocate parts to categories.")}
        </p>
        <.link navigate={~p"/plan?#{%{year: @month.year}}"} class="btn">{gettext("Yearly Plan")}</.link>
        <div :if={@whole && @whole["unallocated"] > 0} class="card border p-5 space-y-2">
          <h2 class="text-xl font-semibold">{gettext("Unallocated this year")}</h2>
          <p id="unallocated-amount">{money(@whole["unallocated"])}</p>
          <.link navigate={~p"/plan?#{%{year: @month.year}}"} class="link">{gettext("Allocate Budget")}</.link>
        </div>
        <div :if={@whole && @whole["unbudgeted"]["remaining"] < 0} class="card border p-5 space-y-2">
          <h2 class="text-xl font-semibold">{gettext("Unbudgeted spending")}</h2>
          <p id="unbudgeted-spent" class={color(-@whole["unbudgeted"]["spent"])}>
            {gettext("%{amount} this month", amount: money(-@whole["unbudgeted"]["spent"]))}
          </p>
          <p>
            {gettext("Spending without a category budget reduces your overall remaining balance.")}
          </p>
        </div>
        <ul class="divide-y divide-base-300">
          <li
            :for={
              item <-
                Enum.reject(@overview, fn item ->
                  @plan && item.category.id == @plan.free_category_id
                end)
            }
            class="py-4 flex flex-wrap justify-between gap-3"
          >
            <div>
              <h2 class="font-semibold">
                {category_label(item.category, @ledger.plans, @ledger.budgets, @month.year)}
              </h2>
              <p class="text-sm">
                {gettext("%{amount} spent", amount: money(item.result["spent"]))} · {if @plan &&
                                                                                          !item.budget,
                                                                                        do:
                                                                                          gettext(
                                                                                            "No budget assigned"
                                                                                          ),
                                                                                        else:
                                                                                          gettext(
                                                                                            "%{amount} available",
                                                                                            amount:
                                                                                              money(
                                                                                                item.result[
                                                                                                  "allocation"
                                                                                                ] +
                                                                                                  item.result[
                                                                                                    "carryover"
                                                                                                  ]
                                                                                              )
                                                                                          )}
              </p>
              <.link :if={@plan} navigate={~p"/plan?#{%{year: @month.year}}"} class="link">{gettext(
                "Edit allocation"
              )}</.link>
              <button
                :if={!@plan}
                type="button"
                phx-click="edit_budget"
                phx-value-id={item.category.id}
                class="link"
              >{gettext("Edit yearly budget")}</button>
            </div>
            <p :if={!@plan || item.budget} class={color(item.result["remaining"])}>
              {money(abs(item.result["remaining"]))} {if item.result["remaining"] < 0,
                do: gettext("over budget"),
                else: gettext("left")}
            </p>
          </li>
        </ul>
      </section>
      <section
        :if={@conflict}
        id="sync-conflict"
        class="border border-warning rounded-box p-5 space-y-3"
        role="alert"
      >
        <h2 class="font-semibold">{gettext("This item changed elsewhere")}</h2>
        <p>
          {if @conflict.current["deleted"],
            do:
              gettext(
                "Your attempted values are preserved in the form. The server version was deleted."
              ),
            else:
              gettext(
                "Your attempted values are preserved in the form. The server version is still available."
              )}
        </p>
        <p :if={@conflict.current["payload"]["amount"]}>
          {gettext("Server amount: %{amount}", amount: money(@conflict.current["payload"]["amount"]))}
        </p>
        <p :if={@conflict.current["payload"]["description"]}>
          {gettext("Server description: %{description}",
            description: @conflict.current["payload"]["description"]
          )}
        </p>
        <button type="button" class="btn" phx-click="use_server">{gettext("Use Server Version")}</button>
        <button
          type="button"
          class="btn btn-primary"
          phx-click="keep_mine"
          phx-disable-with={gettext("Saving…")}
        >
          {if @conflict.current["deleted"],
            do: gettext("Save My Changes as a New Expense"),
            else: gettext("Keep My Changes")}
        </button>
      </section>
      <section
        :if={!@plan && Enum.any?(@ledger.budgets, &(&1.amount > 0))}
        class="space-y-4 pt-8"
        id="yearly-plan"
      >
        <h2 class="text-xl font-semibold">{gettext("Yearly Plan")}</h2>
        <p class="text-sm">
          {gettext(
            "Changing a yearly amount recalculates that entire year. Carryover resets on January 1."
          )}
        </p>
        <.form
          for={@budget_form}
          id="budget-form"
          phx-change="budget_change"
          phx-submit="save_budget"
          class="space-y-3"
        >
          <.input field={@budget_form[:id]} type="hidden" />
          <.input field={@budget_form[:operationID]} type="hidden" />
          <.input field={@budget_form[:revision]} type="hidden" />
          <.input
            field={@budget_form[:categoryID]}
            type="select"
            label={gettext("Category")}
            prompt={gettext("New category")}
            options={Enum.map(@ledger.categories, &{&1.name, &1.id})}
          />
          <.input field={@budget_form[:name]} label={gettext("New category name")} />
          <.input
            field={@budget_form[:year]}
            type="number"
            label={gettext("Year")}
            min="1900"
            max="9999"
            required
          />
          <.currency_input
            field={@budget_form[:amount]}
            label={gettext("Yearly amount (€)")}
            required
          />
          <button
            type="submit"
            class="btn btn-primary"
            phx-disable-with={gettext("Saving…")}
            data-confirm={
              gettext("Save this budget and recalculate all twelve months of the selected year?")
            }
          >{gettext("Save Yearly Budget")}</button>
          <button type="button" class="btn btn-ghost" phx-click="new_budget">{gettext("New Category")}</button>
        </.form>
      </section>
      <section class="space-y-4 pt-8" id="expenses">
        <h2 class="text-xl font-semibold">{gettext("Bookings")}</h2>
        <.form
          for={@expense_form}
          id="expense-form"
          phx-change="expense_change"
          phx-submit="save_expense"
          class="space-y-3"
        >
          <.input
            :for={field <- [:id, :operationID, :revision, :createdAt]}
            field={@expense_form[field]}
            type="hidden"
          />
          <.input
            field={@expense_form[:kind]}
            type="select"
            label={gettext("Type")}
            options={[{gettext("Expense"), "expense"}, {gettext("Income"), "income"}]}
          />
          <.currency_input
            field={@expense_form[:amount]}
            label={gettext("Amount (%{currency})", currency: @expense_form[:currency].value || "EUR")}
            required
          />
          <.input
            field={@expense_form[:currency]}
            type="select"
            label={gettext("Currency")}
            options={["EUR" | MoneyTrack.Currency.currencies()]}
          />
          <p class="text-sm text-base-content/70">
            {gettext(
              "Foreign amounts are converted to euros using the latest available ECB reference rate when saved. Original amount and rate remain in details."
            )}
          </p>
          <.input
            :if={
              @expense_form[:revision].value == "0" && @expense_form[:kind].value != "income" &&
                @sharing_connections != []
            }
            field={@expense_form[:shareWith]}
            type="select"
            label={gettext("Share with")}
            prompt={gettext("Personal")}
            options={Enum.map(@sharing_connections, &{&1["otherName"], &1["otherID"]})}
          />
          <.input field={@expense_form[:description]} label={gettext("Description")} maxlength="500" />
          <.input
            field={@expense_form[:categoryID]}
            type="select"
            label={gettext("Category")}
            prompt={gettext("Choose a category")}
            options={expense_category_options(@ledger, @expense_form[:day].value, @month.year)}
            required
          />
          <.input
            field={@expense_form[:day]}
            type="date"
            phx-hook="LocalExpenseDay"
            data-entry-id={@expense_form[:id].value}
            data-new={@expense_form[:revision].value == "0"}
            label={gettext("Date")}
            required
          />
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving…")}>{if @expense_form[
                                                                                                    :kind
                                                                                                  ].value ==
                                                                                                    "income",
                                                                                                  do:
                                                                                                    gettext(
                                                                                                      "Save Income"
                                                                                                    ),
                                                                                                  else:
                                                                                                    gettext(
                                                                                                      "Save Expense"
                                                                                                    )}</button>
          <button type="button" class="btn btn-ghost" phx-click="cancel_expense">{gettext(
            "New Booking"
          )}</button>
        </.form>
        <ul class="divide-y divide-base-300">
          <li
            :for={
              expense <-
                Enum.filter(
                  @ledger.expenses,
                  &(&1.expense_date.year == @month.year && &1.expense_date.month == @month.month)
                )
            }
            id={"expense-#{expense.id}"}
            class="py-4 space-y-2"
          >
            <div class="flex justify-between gap-4">
              <span>{expense.description}</span><span class={
                color(if expense.kind == "income", do: expense.amount, else: -expense.personal_share)
              }>
                {if expense.kind == "income",
                  do: "+" <> money(expense.amount),
                  else: money(-expense.personal_share)}
              </span>
            </div>
            <p class="text-sm">
              {MoneyTrackWeb.Language.date(expense.expense_date)} · {if expense.kind == "income",
                do: gettext("Income"),
                else: gettext("Expense")} · {Enum.find_value(@ledger.categories, "", fn c ->
                if c.id == expense.category_id,
                  do: category_label(c, @ledger.plans, @ledger.budgets, expense.expense_date.year)
              end)}
            </p>
            <details :if={expense.conversion}>
              <summary>{gettext("Original currency details")}</summary>
              <p>
                {MoneyTrack.Currency.original_input(expense.conversion)} {expense.conversion[
                  "originalCurrency"
                ]} · 1 EUR = {expense.conversion["rate"]} · {gettext("ECB")} {expense.conversion[
                  "rateDate"
                ]}
              </p>
            </details>
            <button
              type="button"
              class="btn btn-sm"
              phx-click="edit_expense"
              phx-value-id={expense.id}
            >{gettext("Edit")}</button>
            <.link
              :if={expense.kind != "income"}
              navigate={~p"/shared?#{%{expense: expense.id}}"}
              class="btn btn-sm"
            >{gettext("Sharing")}</.link>
            <button
              type="button"
              class="btn btn-sm"
              phx-click="delete_expense"
              phx-value-id={expense.id}
              phx-value-revision={expense.revision}
              data-confirm={
                if expense.kind == "income",
                  do: gettext("Delete this income booking?"),
                  else: gettext("Delete this expense and restore its budget impact?")
              }
            >{gettext("Delete")}</button>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
