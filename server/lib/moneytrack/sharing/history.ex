defmodule MoneyTrack.Sharing.History do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "shared_history" do
    field :expense_id, :binary_id
    field :actor_id, :binary_id
    field :action, :string
    field :revision, :integer
    field :changes, :map
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
