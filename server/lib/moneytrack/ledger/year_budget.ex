defmodule MoneyTrack.Ledger.YearBudget do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "year_budgets" do
    field :user_id, :binary_id
    field :category_id, :binary_id
    field :year, :integer
    field :amount, :integer
    field :revision, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end
end
