defmodule MoneyTrack.Ledger.ProcessedOperation do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "processed_operations" do
    field :user_id, :binary_id
    field :operation_id, :binary_id
    field :fingerprint, :binary
    field :result, :map
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
