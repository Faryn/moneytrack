defmodule MoneyTrack.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users" do
    field :username, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    timestamps(type: :utc_datetime_usec)
  end

  def normalize_username(value) when is_binary(value),
    do: value |> String.trim() |> String.downcase()

  def normalize_username(_), do: ""

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :password])
    |> update_change(:username, &normalize_username/1)
    |> validate_required([:username, :password])
    |> validate_format(:username, ~r/\A[a-z0-9][a-z0-9_.-]{2,31}\z/)
    |> validate_length(:password, min: 12, max: 72, count: :bytes)
    |> unique_constraint(:username)
    |> hash_password()
  end

  defp hash_password(%{valid?: true} = changeset) do
    hash = Bcrypt.hash_pwd_salt(get_change(changeset, :password))
    changeset |> put_change(:hashed_password, hash) |> delete_change(:password)
  end

  defp hash_password(changeset), do: changeset
end
