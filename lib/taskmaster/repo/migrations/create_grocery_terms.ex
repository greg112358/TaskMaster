defmodule Taskmaster.Repo.Migrations.CreateGroceryTerms do
  use Ecto.Migration

  def up do
    create table(:grocery_terms) do
      add :name, :string, null: false
      add :category, :string, null: false, default: "other"
      timestamps()
    end

    create unique_index(:grocery_terms, [:name])

    # Seed the built-in vocabulary so the dictionary is useful (and editable)
    # from the first launch. Referencing app code from a migration is normally
    # a smell; this one only reads a static list of {name, category} pairs and
    # writes columns this same migration just created.
    flush()

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.map(Taskmaster.Grocery.DefaultTerms.all(), fn {name, category} ->
        %{name: name, category: category, inserted_at: now, updated_at: now}
      end)

    Taskmaster.Repo.insert_all("grocery_terms", rows, on_conflict: :nothing)
  end

  def down do
    drop table(:grocery_terms)
  end
end
