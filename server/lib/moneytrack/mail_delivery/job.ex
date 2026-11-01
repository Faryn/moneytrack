defmodule MoneyTrack.MailDelivery.Job do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "mail_jobs" do
    field :challenge_id, :binary_id
    field :encrypted_payload, :string, redact: true
    field :status, :string, default: "queued"
    field :attempts, :integer, default: 0
    field :available_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
