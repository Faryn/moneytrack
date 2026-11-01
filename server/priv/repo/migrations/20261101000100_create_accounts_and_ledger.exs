defmodule MoneyTrack.Repo.Migrations.CreateAccountsAndLedger do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :username, :string, null: false
      add :hashed_password, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:username])

    create table(:sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :kind, :string, null: false
      add :label, :string, null: false
      add :expires_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:sessions, [:token_hash])
    create index(:sessions, [:user_id])

    create table(:categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :name_key, :string, null: false
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:categories, [:user_id, :name_key])

    create table(:year_budgets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :category_id, references(:categories, type: :binary_id), null: false
      add :year, :integer, null: false
      add :amount, :bigint, null: false
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:year_budgets, [:user_id, :category_id, :year])

    create constraint(:year_budgets, :valid_budget,
             check: "amount >= 0 AND amount <= 99999999999 AND year BETWEEN 1900 AND 9999"
           )

    create table(:expenses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :category_id, references(:categories, type: :binary_id), null: false
      add :amount, :bigint, null: false
      add :personal_share, :bigint, null: false
      add :description, :string, null: false, default: ""
      add :expense_date, :date, null: false
      add :currency, :string, null: false, default: "EUR"
      add :client_created_at, :utc_datetime, null: false
      add :deleted_at, :utc_datetime_usec
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create index(:expenses, [:user_id, :expense_date])

    create constraint(:expenses, :valid_expense,
             check:
               "amount > 0 AND amount <= 99999999999 AND personal_share >= 0 AND personal_share <= amount AND currency = 'EUR'"
           )

    create table(:processed_operations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :operation_id, :binary_id, null: false
      add :fingerprint, :binary, null: false
      add :result, :map, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:processed_operations, [:user_id, :operation_id])

    create table(:user_changes) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :sequence, :bigint, null: false
      add :record, :map, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:user_changes, [:user_id, :sequence])
  end
end
