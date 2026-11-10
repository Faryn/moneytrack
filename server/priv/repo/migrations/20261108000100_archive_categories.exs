defmodule MoneyTrack.Repo.Migrations.ArchiveCategories do
  use Ecto.Migration

  def change do
    alter table(:categories) do
      add(:archived, :boolean, null: false, default: false)
    end

    drop(unique_index(:categories, [:user_id, :name_key]))
    create(unique_index(:categories, [:user_id, :name_key], where: "archived = 0"))
  end
end
