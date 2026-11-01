defmodule MoneyTrack.Ledger.Category do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "categories" do
    field :user_id, :binary_id
    field :name, :string
    field :name_key, :string
    field :revision, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end
end
