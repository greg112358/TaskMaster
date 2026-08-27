defmodule Taskmaster.Grocery.Term do
  @moduledoc """
  One word the board knows, and which list it belongs on.

  Names are stored lowercased and trimmed — `Dictionary.normalize/1` is the only
  thing that should be producing them.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "grocery_terms" do
    field :name, :string
    field :category, :string, default: "other"
    timestamps()
  end

  def changeset(term, attrs) do
    term
    |> cast(attrs, [:name, :category])
    |> update_change(:name, &Taskmaster.Grocery.Dictionary.normalize/1)
    |> validate_required([:name, :category])
    |> validate_length(:name, min: 1, max: 60)
    |> validate_inclusion(:category, ["meat_dairy", "produce", "other"])
    |> unique_constraint(:name)
  end
end
