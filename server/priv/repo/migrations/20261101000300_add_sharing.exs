defmodule MoneyTrack.Repo.Migrations.AddSharing do
  use Ecto.Migration

  def change do
    create table(:sharing_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_low, references(:users, type: :binary_id), null: false
      add :user_high, references(:users, type: :binary_id), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:sharing_connections, [:user_low, :user_high])
    create constraint(:sharing_connections, :different_people, check: "user_low < user_high")

    create table(:shared_expenses, primary_key: false) do
      add :id, references(:expenses, type: :binary_id), primary_key: true
      add :creator_id, references(:users, type: :binary_id), null: false
      add :recipient_id, references(:users, type: :binary_id)
      add :recipient_email, :text
      add :connection_id, references(:sharing_connections, type: :binary_id)
      add :status, :text, null: false
      add :amount, :bigint, null: false
      add :description, :text, null: false
      add :expense_date, :date, null: false
      add :client_created_at, :utc_datetime, null: false
      add :paid_by_creator, :boolean, null: false
      add :creator_split, :text, null: false
      add :revision, :integer, null: false, default: 1
      add :deleted_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:shared_expenses, [:creator_id])
    create index(:shared_expenses, [:recipient_id])
    create index(:shared_expenses, [:recipient_email, :status])

    create constraint(:shared_expenses, :valid_shared_expense,
             check:
               "amount > 0 AND amount <= 99999999999 AND creator_split IN ('all','half','none') AND status IN ('pending','accepted') AND (recipient_id IS NULL OR recipient_id != creator_id)"
           )

    create table(:shared_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :expense_id, references(:shared_expenses, type: :binary_id), null: false
      add :user_id, references(:users, type: :binary_id), null: false
      add :category_id, references(:categories, type: :binary_id), null: false
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:shared_assignments, [:expense_id, :user_id])

    create table(:shared_history, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :expense_id, references(:shared_expenses, type: :binary_id), null: false
      add :actor_id, references(:users, type: :binary_id), null: false
      add :action, :text, null: false
      add :revision, :integer, null: false
      add :changes, :map, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:shared_history, [:expense_id])

    create table(:sharing_invitation_receipts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :expense_id, references(:shared_expenses, type: :binary_id), null: false
      add :user_id, references(:users, type: :binary_id), null: false
      add :revision, :integer, null: false
    end

    create unique_index(:sharing_invitation_receipts, [:expense_id, :user_id])

    create table(:shared_repayments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :connection_id, references(:sharing_connections, type: :binary_id), null: false
      add :payer_id, references(:users, type: :binary_id), null: false
      add :recipient_id, references(:users, type: :binary_id), null: false
      add :actor_id, references(:users, type: :binary_id), null: false
      add :amount, :bigint, null: false
      add :repayment_date, :date, null: false
      add :client_created_at, :utc_datetime, null: false
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create index(:shared_repayments, [:connection_id])

    create constraint(:shared_repayments, :valid_repayment,
             check: "amount > 0 AND amount <= 99999999999 AND payer_id != recipient_id"
           )

    create table(:sharing_mail_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :expense_id, references(:shared_expenses, type: :binary_id), null: false
      add :status, :text, null: false, default: "queued"
      add :attempts, :integer, null: false, default: 0
      add :available_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:sharing_mail_jobs, [:expense_id])
  end
end
