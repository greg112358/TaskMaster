defmodule Taskmaster.Grocery do
  import Ecto.Query
  alias Taskmaster.Repo
  alias Taskmaster.Grocery.Dictionary
  alias Taskmaster.Grocery.Item

  @topic "groceries"

  def subscribe do
    Phoenix.PubSub.subscribe(Taskmaster.PubSub, @topic)
  end

  defp broadcast do
    Phoenix.PubSub.broadcast(Taskmaster.PubSub, @topic, :groceries_changed)
  end

  def list_items do
    Repo.all(from i in Item, order_by: [asc: i.inserted_at])
  end

  def list_items_by_category(category) do
    Repo.all(from i in Item, where: i.category == ^category, order_by: [asc: i.inserted_at])
  end

  @doc """
  Adds an item, letting the dictionary decide which list it lands on. Words the
  dictionary does not know go to "everything else" — use `add_item/2` where
  there is somebody to ask.
  """
  def add_item(name), do: add_item(name, Dictionary.category_for!(name))

  @doc "Adds an item to a category the caller has already decided on."
  def add_item(name, category) do
    %Item{}
    |> Item.changeset(%{name: name, category: category})
    |> Repo.insert()
    |> tap(fn
      {:ok, _} -> broadcast()
      _ -> :ok
    end)
  end

  def toggle_item(id) do
    item = Repo.get!(Item, id)

    item
    |> Item.changeset(%{checked: !item.checked})
    |> Repo.update()
    |> tap(fn
      {:ok, _} -> broadcast()
      _ -> :ok
    end)
  end

  def delete_item(id) do
    Repo.get!(Item, id)
    |> Repo.delete()
    |> tap(fn
      {:ok, _} -> broadcast()
      _ -> :ok
    end)
  end

  def clear_all do
    Repo.delete_all(Item)
    broadcast()
  end
end
