defmodule MoneyTrack.Repo.Migrations.AddIncome do
  use Ecto.Migration

  def change do
    alter table(:expenses) do
      add(:kind, :string, null: false, default: "expense")
    end

    create(constraint(:expenses, :valid_entry_kind, check: "kind IN ('expense', 'income')"))
  end
end
