defmodule Taskmaster.Grocery do
  import Ecto.Query
  alias Taskmaster.Repo
  alias Taskmaster.Grocery.Item
  alias Taskmaster.Grocery.Categorizer

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

  def add_item(name) do
    category = Categorizer.categorize(name)

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
