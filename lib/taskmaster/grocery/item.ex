defmodule Taskmaster.Grocery.Item do
  use Ecto.Schema
  import Ecto.Changeset

  schema "grocery_items" do
    field :name, :string
    field :category, :string, default: "other"
    field :checked, :boolean, default: false
    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:name, :category, :checked])
    |> validate_required([:name, :category])
    |> validate_inclusion(:category, ["meat_dairy", "produce", "other"])
  end
end
