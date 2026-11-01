defmodule MoneyTrack.Accounts.EmailChallenge do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "email_challenges" do
    field :user_id, :binary_id
    field :address, :string
    field :code_hash, :string, redact: true
    field :attempts, :integer, default: 0
    field :expires_at, :utc_datetime_usec
    field :retired_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
