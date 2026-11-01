defmodule MoneyTrack.Ledger.UserChange do
  use Ecto.Schema

  schema "user_changes" do
    field :user_id, :binary_id
    field :sequence, :integer
    field :record, :map
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
