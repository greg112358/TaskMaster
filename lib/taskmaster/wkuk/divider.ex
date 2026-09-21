defmodule Taskmaster.Wkuk.Divider do
  @moduledoc """
  A tier boundary in one person's list.

  A sketch has no stored tier. Its tier is whichever divider sits above it, so
  dragging a divider re-tiers everything it crosses in one move — which is the
  whole reason the dividers are draggable.

  There are eight, and `unranked` is one of them: it is the floor of the ranked
  region, everything below it is unranked, and it is the only one that cannot be
  dragged. Keeping it in the same table means the list is one ordered sequence
  with no special case at the bottom.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @tiers ~w(S A B C D E F unranked)
  @ranked_tiers ~w(S A B C D E F)

  schema "wkuk_dividers" do
    field :user, :string
    field :tier, :string
    field :position, :integer
    timestamps()
  end

  @doc "Every divider, top to bottom. This order is enforced on every move."
  def tiers, do: @tiers

  @doc "The seven a person can drag. `unranked` is fixed."
  def ranked_tiers, do: @ranked_tiers

  @doc "True for the tiers that hold a ranking, false for `unranked`."
  def ranked?(tier), do: tier in @ranked_tiers

  def changeset(divider, attrs) do
    divider
    |> cast(attrs, [:user, :tier, :position])
    |> validate_required([:user, :tier, :position])
    |> validate_inclusion(:tier, @tiers)
    |> unique_constraint([:user, :tier])
  end
end
