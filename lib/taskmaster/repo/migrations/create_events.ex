defmodule Taskmaster.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :title, :string, null: false
      add :type, :string, null: false, default: "task"
      add :person_id, references(:people, on_delete: :nilify_all)
      add :start_date, :date, null: false
      add :recurrence_type, :string
      add :recurrence_interval, :integer, default: 1
      add :recurrence_day_of_week, :integer
      add :last_completed_at, :naive_datetime
      timestamps()
    end

    create index(:events, [:person_id])
    create index(:events, [:start_date])
  end
end
