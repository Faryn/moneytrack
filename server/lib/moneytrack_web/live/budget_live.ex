defmodule MoneyTrackWeb.BudgetLive do
  use MoneyTrackWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Budget")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="budget-overview" aria-labelledby="budget-heading" class="space-y-8">
        <div>
          <p class="text-sm text-base-content/60">This month</p>
          <h1 id="budget-heading" class="text-3xl font-semibold tracking-tight">Your budget</h1>
        </div>
        <div class="rounded-box border border-base-300 bg-base-200 px-6 py-12 text-center">
          <.icon name="hero-chart-pie" class="mx-auto mb-4 size-10 text-base-content/50" />
          <h2 class="text-lg font-medium">No budget yet</h2>
          <p class="mx-auto mt-2 max-w-sm text-base-content/60">
            Your monthly budget and remaining amount will appear here.
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
