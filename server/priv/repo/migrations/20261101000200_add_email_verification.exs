defmodule MoneyTrack.Repo.Migrations.AddEmailVerification do
  use Ecto.Migration

  def change do
    create table(:verified_emails, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :address, :text, null: false
      add :verified_at, :utc_datetime_usec, null: false
    end

    create unique_index(:verified_emails, [:user_id])
    create unique_index(:verified_emails, [:address])

    create table(:email_challenges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :address, :text, null: false
      add :code_hash, :text, null: false
      add :attempts, :integer, null: false, default: 0
      add :expires_at, :utc_datetime_usec, null: false
      add :retired_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:email_challenges, [:user_id, :inserted_at])

    create table(:mail_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :challenge_id, references(:email_challenges, type: :binary_id, on_delete: :delete_all),
        null: false

      add :encrypted_payload, :text
      add :status, :text, null: false, default: "queued"
      add :attempts, :integer, null: false, default: 0
      add :available_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:mail_jobs, [:challenge_id])
    create index(:mail_jobs, [:status, :available_at])
  end
end
