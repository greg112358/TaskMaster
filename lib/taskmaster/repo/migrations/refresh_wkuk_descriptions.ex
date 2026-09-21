defmodule Taskmaster.Repo.Migrations.RefreshWkukDescriptions do
  use Ecto.Migration

  @moduledoc """
  Replaces the first-draft sketch descriptions with the synopsis-based ones, on
  databases that were seeded before the catalogue was rewritten.

  Only rows nobody has edited are touched; see
  `Taskmaster.Wkuk.refresh_unedited_descriptions/0`. On a database seeded after
  the rewrite this changes nothing.

  Like migration 5 and 7 this reads app code, and for the same reason: it only
  reads a static list and writes columns that already exist.
  """

  def up do
    flush()
    Taskmaster.Wkuk.refresh_unedited_descriptions()
  end

  def down, do: :ok
end
