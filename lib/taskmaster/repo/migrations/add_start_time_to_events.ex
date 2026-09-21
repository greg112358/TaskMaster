defmodule Taskmaster.Repo.Migrations.AddStartTimeToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      # The wall-clock time the event starts, Pacific like everything else
      # (`Taskmaster.Clock`). Null is an all-day row, which is what every
      # existing row becomes — the column is deliberately nullable rather than
      # defaulted to midnight, since "no time" and "00:00" read differently on
      # the calendar and fire differently as alerts.
      add :start_time, :time
    end
  end
end
