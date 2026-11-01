defmodule MoneyTrack.Sharing.SharedExpense do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "shared_expenses" do
    field :creator_id, :binary_id
    field :recipient_id, :binary_id
    field :recipient_email, :string
    field :connection_id, :binary_id
    field :status, :string
    field :amount, :integer
    field :description, :string
    field :expense_date, :date
    field :client_created_at, :utc_datetime
    field :paid_by_creator, :boolean
    field :creator_split, :string
    field :revision, :integer, default: 1
    field :deleted_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
