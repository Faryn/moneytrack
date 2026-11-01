defmodule MoneyTrack.Accounts.VerifiedEmail do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "verified_emails" do
    field :user_id, :binary_id
    field :address, :string
    field :verified_at, :utc_datetime_usec
  end

  def changeset(value, attrs) do
    value
    |> Ecto.Changeset.cast(attrs, [:user_id, :address, :verified_at])
    |> Ecto.Changeset.validate_required([:user_id, :address, :verified_at])
    |> Ecto.Changeset.unique_constraint(:user_id)
    |> Ecto.Changeset.unique_constraint(:address)
  end
end
