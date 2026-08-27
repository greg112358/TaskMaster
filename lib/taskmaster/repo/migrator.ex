defmodule Taskmaster.Repo.Migrator do
  @moduledoc """
  Runs embedded migrations at application startup.
  This is needed for Desktop apps where mix ecto.migrate is not available.
  """

  def run do
    Ecto.Migrator.run(Taskmaster.Repo, migrations(), :up, all: true, log: :info)
  end

  defp migrations do
    [
      {1, Taskmaster.Repo.Migrations.CreatePeople},
      {2, Taskmaster.Repo.Migrations.CreateGroceryItems},
      {3, Taskmaster.Repo.Migrations.CreateEvents},
      {4, Taskmaster.Repo.Migrations.AddAlertToEvents},
      {5, Taskmaster.Repo.Migrations.CreateGroceryTerms},
      {6, Taskmaster.Repo.Migrations.ReseedGroceryTerms}
    ]
  end
end
