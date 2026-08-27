defmodule Taskmaster.Repo.Migrations.ReseedGroceryTerms do
  use Ecto.Migration

  @moduledoc """
  Replaces the dictionary seeded by migration 5.

  That first vocabulary was far too long — several hundred entries, most of them
  words no household writes on a list ("anaheim", "ancho", "rambutan") — and its
  multi-word terms had been shredded into fragments by `~w`.

  This wipes `grocery_terms` and re-seeds it. Words the family had taught the
  board go with it. That is acceptable only because nothing has shipped; a
  later change to the defaults must not do this.
  """

  def up do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.map(Taskmaster.Grocery.DefaultTerms.all(), fn {name, category} ->
        %{name: name, category: category, inserted_at: now, updated_at: now}
      end)

    Taskmaster.Repo.delete_all("grocery_terms")
    Taskmaster.Repo.insert_all("grocery_terms", rows)
  end

  def down, do: :ok
end
