defmodule Taskmaster.Wkuk.Ranking do
  @moduledoc """
  One person's placement of one sketch, plus their private notes on it.

  `position` is an index into that person's single ordered list, shared with
  `Taskmaster.Wkuk.Divider` — the two tables interleave in one sequence. Tier is
  not stored here; it is read off the nearest divider above.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "wkuk_rankings" do
    field :user, :string
    field :position, :integer
    field :notes, :string, default: ""
    belongs_to :sketch, Taskmaster.Wkuk.Sketch
    timestamps()
  end

  def changeset(ranking, attrs) do
    ranking
    |> cast(attrs, [:user, :sketch_id, :position, :notes])
    |> validate_required([:user, :sketch_id, :position])
    |> validate_length(:notes, max: 2000)
    |> unique_constraint([:user, :sketch_id])
  end
end
