defmodule MoneyTrackWeb.PlanLive do
  use MoneyTrackWeb, :live_view
  alias MoneyTrack.{Ledger, Repo}
  alias MoneyTrack.Ledger.Category
  @impl true
  def mount(_, _, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(MoneyTrack.PubSub, "ledger:#{socket.assigns.current_user.id}")

    {:ok,
     assign(socket,
       year: Date.utc_today().year,
       form: nil,
       allocation_form: nil,
       allocation_snapshot: nil,
       error: nil,
       conflict: nil
     )}
  end

  @impl true
  def handle_params(params, _, socket) do
    year =
      case Integer.parse(params["year"] || "#{Date.utc_today().year}") do
        {y, ""} when y in 1900..9999 -> y
        _ -> Date.utc_today().year
      end

    {:noreply, socket |> assign(year: year) |> reload() |> total_form()}
  end

  @impl true
  def handle_info(:ledger_changed, socket), do: {:noreply, reload(socket)}
  @impl true
  def handle_event("total_change", %{"plan" => p}, socket),
    do: {:noreply, assign(socket, form: to_form(p, as: :plan))}

  def handle_event("total", %{"plan" => p}, socket) do
    socket = assign(socket, form: to_form(p, as: :plan))

    with {:ok, total} <- parse(p["total"]),
         {:ok, allocations} <- Jason.decode(p["allocations"]),
         true <- is_list(allocations) do
      free = free_category(socket, allocations)

      payload = %{
        "id" => p["id"],
        "year" => socket.assigns.year,
        "total" => total,
        "freeCategoryID" => free.id,
        "allocations" => allocations
      }

      {:noreply, save(socket, operation(payload, integer(p["revision"]), p["operationID"]))}
    else
      _ -> {:noreply, assign(socket, error: "Enter a valid yearly total.")}
    end
  end

  def handle_event("edit_allocation", %{"id" => id}, socket) do
    if socket.assigns.plan &&
         (id == "new" || Enum.any?(socket.assigns.ledger.categories, &(&1.id == id))) do
      p = Ledger.envelope(socket.assigns.plan)["payload"]
      current = Enum.find(p["allocations"], &(&1["categoryID"] == id))

      form = %{
        "categoryID" => if(id == "new", do: Ecto.UUID.generate(), else: id),
        "name" => "",
        "amount" => if(current, do: input_amount(current["amount"]), else: ""),
        "new" => to_string(id == "new"),
        "operationID" => Ecto.UUID.generate()
      }

      {:noreply,
       assign(socket,
         allocation_form: to_form(form, as: :allocation),
         allocation_snapshot: {p, socket.assigns.plan.revision}
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("allocation_change", %{"allocation" => p}, socket),
    do: {:noreply, assign(socket, allocation_form: to_form(p, as: :allocation))}

  def handle_event("allocation", %{"allocation" => p}, socket) do
    socket = assign(socket, allocation_form: to_form(p, as: :allocation))

    with {snapshot, revision} <- socket.assigns.allocation_snapshot,
         {:ok, amount} <- parse(if(p["amount"] == "", do: "0", else: p["amount"])),
         true <-
           amount +
             Enum.sum(
               Enum.map(
                 Enum.reject(snapshot["allocations"], &(&1["categoryID"] == p["categoryID"])),
                 & &1["amount"]
               )
             ) <= snapshot["total"],
         :ok <- ensure_category(socket, p) do
      entries = Enum.reject(snapshot["allocations"], &(&1["categoryID"] == p["categoryID"]))

      entries =
        if amount == 0,
          do: entries,
          else: entries ++ [%{"categoryID" => p["categoryID"], "amount" => amount}]

      payload = Map.put(snapshot, "allocations", entries)
      {:noreply, save(socket, operation(payload, revision, p["operationID"]))}
    else
      _ ->
        {:noreply,
         assign(socket,
           error: "Enter a category and allocation that fits within the yearly total."
         )}
    end
  end

  def handle_event("cancel", _, socket),
    do: {:noreply, assign(socket, allocation_form: nil, allocation_snapshot: nil, error: nil)}

  def handle_event("use_server", _, socket),
    do:
      {:noreply,
       socket
       |> assign(conflict: nil, error: nil, allocation_form: nil, allocation_snapshot: nil)
       |> reload()
       |> total_form()}

  def handle_event("keep_local", _, socket) do
    case socket.assigns.conflict do
      %{operation: op, current: current} ->
        updated =
          op
          |> Map.put("operationID", Ecto.UUID.generate())
          |> Map.put("entityID", current["entityID"])
          |> Map.put("expectedRevision", current["revision"])
          |> Map.update!("payload", &Map.put(&1, "id", current["entityID"]))

        {:noreply, save(socket, updated)}

      _ ->
        {:noreply, socket}
    end
  end

  defp save(socket, op) do
    case Ledger.apply_operation(socket.assigns.current_user, op) do
      {:ok, _} ->
        socket
        |> assign(error: nil, conflict: nil, allocation_form: nil, allocation_snapshot: nil)
        |> reload()
        |> total_form()

      {:error, {:conflict, current}} ->
        socket
        |> assign(
          error: "This year's plan changed. Review the server plan before replacing it.",
          conflict: %{operation: op, current: current}
        )
        |> reload()

      {:error, {:validation, message}} ->
        assign(socket, error: message)

      _ ->
        assign(socket, error: "This plan or category is unavailable.")
    end
  end

  defp reload(socket) do
    ledger = Ledger.snapshot(socket.assigns.current_user)

    assign(socket,
      ledger: ledger,
      plan: Enum.find(ledger.plans, &(&1.year == socket.assigns.year))
    )
  end

  defp total_form(socket) do
    plan = socket.assigns.plan

    allocations =
      if plan,
        do: plan.allocations["items"],
        else:
          for(
            b <- socket.assigns.ledger.budgets,
            b.year == socket.assigns.year and b.amount > 0,
            do: %{"categoryID" => b.category_id, "amount" => b.amount}
          )

    total = if plan, do: plan.total, else: Enum.sum(Enum.map(allocations, & &1["amount"]))

    form = %{
      "id" => if(plan, do: plan.id, else: Ecto.UUID.generate()),
      "revision" => if(plan, do: "#{plan.revision}", else: "0"),
      "total" => if(total == 0 && !plan, do: "", else: input_amount(total)),
      "allocations" => Jason.encode!(allocations),
      "operationID" => Ecto.UUID.generate()
    }

    assign(socket, form: to_form(form, as: :plan))
  end

  defp free_category(socket, allocations) do
    if socket.assigns.plan do
      Repo.get!(Category, socket.assigns.plan.free_category_id)
    else
      ids = Enum.map(allocations, & &1["categoryID"])
      candidates = socket.assigns.ledger.categories

      found =
        Enum.find(candidates, &(&1.name_key == "uncategorized" && &1.id not in ids)) ||
          Enum.find(candidates, &(&1.name_key == "guilt-free spending" && &1.id not in ids))

      if found do
        found
      else
        name =
          if Enum.any?(candidates, &(&1.name_key == "uncategorized")),
            do: "Guilt-free spending",
            else: "Uncategorized"

        name = unique_name(name, candidates)
        id = Ecto.UUID.generate()

        {:ok, _} =
          Ledger.apply_operation(socket.assigns.current_user, %{
            "operationID" => Ecto.UUID.generate(),
            "entity" => "category",
            "entityID" => id,
            "action" => "upsert",
            "expectedRevision" => 0,
            "payload" => %{"id" => id, "name" => name}
          })

        Repo.get!(Category, id)
      end
    end
  end

  defp unique_name(base, categories) do
    Enum.find_value(1..1000, fn n ->
      name = if n == 1, do: base, else: "#{base} #{n}"
      unless Enum.any?(categories, &(&1.name_key == String.downcase(name))), do: name
    end) || raise "too many default-category names"
  end

  defp ensure_category(socket, p) do
    if p["new"] == "true" do
      op = %{
        "operationID" => p["categoryID"],
        "entity" => "category",
        "entityID" => p["categoryID"],
        "action" => "upsert",
        "expectedRevision" => 0,
        "payload" => %{"id" => p["categoryID"], "name" => p["name"]}
      }

      case Ledger.apply_operation(socket.assigns.current_user, op) do
        {:ok, _} -> :ok
        _ -> :error
      end
    else
      :ok
    end
  end

  defp operation(payload, revision, id),
    do: %{
      "operationID" => id,
      "entity" => "budget_plan",
      "entityID" => payload["id"],
      "action" => "upsert",
      "expectedRevision" => revision,
      "payload" => payload
    }

  defp integer(v) do
    case Integer.parse(v || "") do
      {n, ""} -> n
      _ -> -1
    end
  end

  defp parse(v) when is_binary(v) do
    v = v |> String.trim() |> String.replace(",", ".")

    if byte_size(v) <= 16 && Regex.match?(~r/\A[0-9]+(?:\.[0-9]{1,2})?\z/, v) do
      [whole | rest] = String.split(v, ".")

      fraction =
        case rest do
          [] -> 0
          [n] -> String.to_integer(String.pad_trailing(n, 2, "0"))
        end

      amount = String.to_integer(whole) * 100 + fraction
      if amount <= 99_999_999_999, do: {:ok, amount}, else: :error
    else
      :error
    end
  end

  defp parse(_), do: :error
  defp input_amount(n), do: "#{div(n, 100)}.#{String.pad_leading(to_string(rem(n, 100)), 2, "0")}"
  defp money(n), do: "€" <> input_amount(n)
  @impl true
  def render(assigns) do
    assigned =
      if assigns.plan,
        do: Enum.sum(Enum.map(assigns.plan.allocations["items"], & &1["amount"])),
        else: 0

    assigns = assign(assigns, assigned: assigned)

    ~H"""
    <Layouts.app flash={@flash} current_scope={%{user: @current_user}}>
      <.link navigate={~p"/?#{%{month: "#{@year}-01"}}"} class="link">Budget</.link>
      <h1 class="text-2xl font-semibold">Yearly Plan · {@year}</h1>
      <p :if={@error} id="plan-error" role="alert" class="text-error">{@error}</p>
      <section :if={@conflict} id="plan-conflict" class="card border border-warning p-4">
        <p>Server yearly total: {money(@conflict.current["payload"]["total"])}</p>
        <p :for={a <- @conflict.current["payload"]["allocations"]}>
          {Enum.find_value(@ledger.categories, "Category", fn c ->
            if c.id == a["categoryID"], do: c.name
          end)}: {money(a["amount"])}
        </p>
        <button phx-click="use_server" class="btn">Use Server Plan</button><button
          phx-click="keep_local"
          class="btn"
        >Keep My Plan</button>
      </section>
      <.form
        :if={@form}
        for={@form}
        id="whole-budget-form"
        phx-submit="total"
        phx-change="total_change"
        class="card border p-4"
      >
        <h2 class="text-xl font-semibold">1. Pick the Whole Yearly Budget</h2>
        <.input
          :for={key <- [:id, :revision, :allocations, :operationID]}
          field={@form[key]}
          type="hidden"
        />
        <.input field={@form[:total]} label="Yearly budget (€)" inputmode="decimal" required />
        <p>
          Category allocations come from this total. Everything unassigned is guilt-free spending.
        </p>
        <.button
          phx-disable-with="Saving…"
          data-confirm={@plan && "Recalculate this whole calendar year with the new budget?"}
        >Save Yearly Budget</.button>
      </.form>
      <section :if={@plan} id="plan-summary" class="card border p-4 space-y-2">
        <p>Yearly total: {money(@plan.total)}</p><p>Allocated: {money(@assigned)}</p><p>
          Guilt-free: {money(@plan.total - @assigned)}
        </p>
      </section>
      <section :if={@plan} class="space-y-3">
        <h2 class="text-xl font-semibold">2. Assign Parts to Categories</h2>
        <div
          :for={c <- @ledger.categories}
          :if={c.id != @plan.free_category_id}
          id={"allocate-#{c.id}"}
        >
          <span>{c.name}: {Enum.find_value(@plan.allocations["items"], "Guilt-free pool", fn a ->
            if a["categoryID"] == c.id, do: money(a["amount"])
          end)}</span>
          <button phx-click="edit_allocation" phx-value-id={c.id} class="btn">Edit Allocation</button>
        </div>
        <button phx-click="edit_allocation" phx-value-id="new" class="btn">Add Category</button>
      </section>
      <p :if={!@plan}>Save the total first to start assigning category amounts.</p>
      <.form
        :if={@allocation_form}
        for={@allocation_form}
        id="allocation-form"
        phx-change="allocation_change"
        phx-submit="allocation"
        class="card border p-4"
      >
        <.input
          :for={key <- [:categoryID, :new, :operationID]}
          field={@allocation_form[key]}
          type="hidden"
        />
        <.input
          :if={@allocation_form.params["new"] == "true"}
          field={@allocation_form[:name]}
          label="Category name"
          required
        />
        <.input
          field={@allocation_form[:amount]}
          label="Yearly allocation (€); zero uses guilt-free"
          inputmode="decimal"
        />
        <.button data-confirm="Recalculate this whole calendar year with these allocations?">Save Allocation</.button><button
          phx-click="cancel"
          type="button"
          class="btn"
        >Cancel</button>
      </.form>
    </Layouts.app>
    """
  end
end
