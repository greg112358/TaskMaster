defmodule Taskmaster.Repo.Migrations.AddAlertToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      # When true, the app chimes and reads the title aloud on the day the
      # event/task is due.
      add :alert, :boolean, null: false, default: false
      # Day the alert last fired, so it only announces once per occurrence
      # even across app restarts.
      add :last_alerted_on, :date
    end

    create index(:events, [:alert])
  end
end
