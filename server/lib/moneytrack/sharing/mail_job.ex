defmodule MoneyTrack.Sharing.MailJob do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sharing_mail_jobs" do
    field :expense_id, :binary_id
    field :status, :string, default: "queued"
    field :attempts, :integer, default: 0
    field :available_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
