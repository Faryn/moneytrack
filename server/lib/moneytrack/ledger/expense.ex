defmodule MoneyTrack.Ledger.Expense do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "expenses" do
    field :user_id, :binary_id
    field :category_id, :binary_id
    field :amount, :integer
    field :personal_share, :integer
    field :description, :string, default: ""
    field :expense_date, :date
    field :currency, :string, default: "EUR"
    field :client_created_at, :utc_datetime
    field :deleted_at, :utc_datetime_usec
    field :revision, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end
end
