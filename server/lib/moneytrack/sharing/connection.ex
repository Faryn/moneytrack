defmodule MoneyTrack.Sharing.Connection do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sharing_connections" do
    field :user_low, :binary_id
    field :user_high, :binary_id
    timestamps(type: :utc_datetime_usec)
  end
end
