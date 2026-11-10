defmodule MoneyTrack.Repo.Migrations.AddCurrencyConversion do
  use Ecto.Migration

  def change do
    alter table(:expenses) do
      add :conversion, :map
    end

    alter table(:shared_expenses) do
      add :conversion, :map
    end
  end
end
