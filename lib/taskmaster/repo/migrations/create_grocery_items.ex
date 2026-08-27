defmodule Taskmaster.Repo.Migrations.CreateGroceryItems do
  use Ecto.Migration

  def change do
    create table(:grocery_items) do
      add :name, :string, null: false
      add :category, :string, null: false, default: "other"
      add :checked, :boolean, default: false
      timestamps()
    end
  end
end
