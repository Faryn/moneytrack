defmodule MoneyTrack.Sharing.Assignment do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "shared_assignments" do
    field :expense_id, :binary_id
    field :user_id, :binary_id
    field :category_id, :binary_id
    field :revision, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end
end
