defmodule MoneyTrack.Repo.Migrations.AddBudgetPlans do
  use Ecto.Migration

  def change do
    create table(:budget_plans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id), null: false
      add :year, :integer, null: false
      add :total, :bigint, null: false
      add :free_category_id, references(:categories, type: :binary_id), null: false
      add :allocations, :map, null: false
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:budget_plans, [:user_id, :year])

    create constraint(:budget_plans, :valid_budget_plan,
             check: "year >= 1900 AND year <= 9999 AND total >= 0 AND total <= 99999999999"
           )
  end
end
