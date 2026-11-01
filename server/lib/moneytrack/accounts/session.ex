defmodule MoneyTrack.Accounts.Session do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sessions" do
    field :user_id, :binary_id
    field :token_hash, :binary, redact: true
    field :kind, :string
    field :label, :string
    field :expires_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
