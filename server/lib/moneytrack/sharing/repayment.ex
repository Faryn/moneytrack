defmodule MoneyTrack.Sharing.Repayment do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "shared_repayments" do
    field :connection_id, :binary_id
    field :payer_id, :binary_id
    field :recipient_id, :binary_id
    field :actor_id, :binary_id
    field :amount, :integer
    field :repayment_date, :date
    field :client_created_at, :utc_datetime
    field :revision, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end
end
