defmodule Taskmaster.People do
  import Ecto.Query
  alias Taskmaster.Repo
  alias Taskmaster.People.Person

  @topic "people"

  def subscribe do
    Phoenix.PubSub.subscribe(Taskmaster.PubSub, @topic)
  end

  defp broadcast do
    Phoenix.PubSub.broadcast(Taskmaster.PubSub, @topic, :people_changed)
  end

  def list_people do
    Repo.all(from p in Person, order_by: p.name)
  end

  def get_person!(id), do: Repo.get!(Person, id)

  @doc "The person, or `nil` when the id is stale. Use this for ids off the wire."
  def get_person(id), do: Repo.get(Person, id)

  def get_person_by_name(name) do
    Repo.get_by(Person, name: name)
  end

  def find_person_by_name(name) do
    name_lower = String.downcase(name)

    list_people()
    |> Enum.find(fn p -> String.downcase(p.name) == name_lower end)
  end

  def create_person(attrs) do
    %Person{}
    |> Person.changeset(attrs)
    |> Repo.insert()
    |> tap(fn
      {:ok, _} -> broadcast()
      _ -> :ok
    end)
  end

  def delete_person(%Person{} = person) do
    Repo.delete(person)
    |> tap(fn
      {:ok, _} -> broadcast()
      _ -> :ok
    end)
  end
end
