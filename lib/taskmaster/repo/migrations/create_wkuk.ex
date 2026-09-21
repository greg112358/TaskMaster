defmodule Taskmaster.Repo.Migrations.CreateWkuk do
  use Ecto.Migration

  @moduledoc """
  The sketch ranking board at `/wkuk`.

  Three tables: the shared sketch catalogue, and per-person rankings and tier
  dividers. Only the catalogue is seeded here — a person's rows are created on
  their first visit by `Taskmaster.Wkuk.ensure_seeded/1`, which also picks up
  any sketch added to the catalogue after this ran.
  """

  def up do
    create table(:wkuk_sketches) do
      add :season, :integer, null: false
      add :episode, :integer, null: false
      add :position, :integer, null: false
      add :title, :string, null: false
      add :description, :string, null: false, default: ""
      add :youtube_url, :string
      timestamps()
    end

    # Two sketches share the title "Timmy Dance" across seasons, so the key is
    # the catalogue slot rather than the title.
    create unique_index(:wkuk_sketches, [:season, :episode, :position])

    create table(:wkuk_rankings) do
      add :user, :string, null: false
      add :sketch_id, references(:wkuk_sketches, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :notes, :text, null: false, default: ""
      timestamps()
    end

    create unique_index(:wkuk_rankings, [:user, :sketch_id])
    create index(:wkuk_rankings, [:user, :position])

    create table(:wkuk_dividers) do
      add :user, :string, null: false
      add :tier, :string, null: false
      add :position, :integer, null: false
      timestamps()
    end

    create unique_index(:wkuk_dividers, [:user, :tier])

    flush()

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.map(Taskmaster.Wkuk.Catalog.all(), fn sketch ->
        sketch
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    Taskmaster.Repo.insert_all("wkuk_sketches", rows, on_conflict: :nothing)
  end

  def down do
    drop table(:wkuk_dividers)
    drop table(:wkuk_rankings)
    drop table(:wkuk_sketches)
  end
end
