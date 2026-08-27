defmodule Taskmaster.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset

  schema "events" do
    field :title, :string
    field :type, :string, default: "task"
    field :start_date, :date
    field :recurrence_type, :string
    field :recurrence_interval, :integer, default: 1
    field :recurrence_day_of_week, :integer
    field :last_completed_at, :naive_datetime
    field :alert, :boolean, default: false
    field :last_alerted_on, :date
    belongs_to :person, Taskmaster.People.Person
    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :title,
      :type,
      :start_date,
      :recurrence_type,
      :recurrence_interval,
      :recurrence_day_of_week,
      :last_completed_at,
      :alert,
      :last_alerted_on,
      :person_id
    ])
    |> validate_required([:title, :type, :start_date])
    |> validate_inclusion(:type, ["task", "event"])
    |> foreign_key_constraint(:person_id)
  end
end
