defmodule MoneyTrack.Ledger.BudgetPlan do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "budget_plans" do
    field :user_id, :binary_id
    field :year, :integer
    field :total, :integer
    field :free_category_id, :binary_id
    field :allocations, :map
    field :revision, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end
end
