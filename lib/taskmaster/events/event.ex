defmodule Taskmaster.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset

  # The rules `Taskmaster.Events.Recurrence` knows how to advance, and the subset
  # of them that counts in intervals.
  @recurrence_types ~w(daily weekly monthly yearly every_n_days every_n_weeks every_n_months)
  @interval_types ~w(every_n_days every_n_weeks every_n_months)

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
    |> validate_inclusion(:recurrence_type, @recurrence_types)
    |> validate_interval()
    |> foreign_key_constraint(:person_id)
  end

  @doc "The recurrence rules that can be stored, for anything offering a choice."
  def recurrence_types, do: @recurrence_types

  # A recurrence is a rule, not a list of rows: `Recurrence.occurrences_in_range/3`
  # steps forward from `start_date` until it passes the end of the range, so it
  # only ever terminates while `next_date/2` strictly advances. An interval of
  # zero or less never advances — the stream runs forever, pinning a core and
  # growing. Worse, the rule is stored, so every later render of the calendar
  # hangs the same way and the board cannot be recovered from its own screen.
  #
  # The interval field is `min="1"` in the form as well, but that is client-side
  # only and the voice parser does not go near it.
  defp validate_interval(changeset) do
    changeset = validate_number(changeset, :recurrence_interval, greater_than: 0)

    if get_field(changeset, :recurrence_type) in @interval_types do
      validate_required(changeset, [:recurrence_interval])
    else
      changeset
    end
  end
end
