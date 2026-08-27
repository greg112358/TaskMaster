defmodule Taskmaster.Events.Recurrence do
  alias Taskmaster.Events.Event

  def occurrences_in_range(%Event{recurrence_type: nil} = event, range_start, range_end) do
    if Date.compare(event.start_date, range_start) != :lt and
         Date.compare(event.start_date, range_end) != :gt do
      [event.start_date]
    else
      []
    end
  end

  def occurrences_in_range(%Event{} = event, range_start, range_end) do
    Stream.iterate(event.start_date, &next_date(event, &1))
    |> Stream.take_while(fn date -> Date.compare(date, range_end) != :gt end)
    |> Enum.filter(fn date -> Date.compare(date, range_start) != :lt end)
  end

  def next_occurrence_from(%Event{recurrence_type: nil} = event, from_date) do
    if Date.compare(event.start_date, from_date) != :lt do
      event.start_date
    else
      nil
    end
  end

  def next_occurrence_from(%Event{} = event, from_date) do
    Stream.iterate(event.start_date, &next_date(event, &1))
    |> Stream.drop_while(fn date -> Date.compare(date, from_date) == :lt end)
    |> Enum.at(0)
  end

  defp next_date(%Event{recurrence_type: "daily"}, current) do
    Date.add(current, 1)
  end

  defp next_date(%Event{recurrence_type: "weekly"}, current) do
    Date.add(current, 7)
  end

  defp next_date(%Event{recurrence_type: "monthly"}, current) do
    shift_months(current, 1)
  end

  defp next_date(%Event{recurrence_type: "yearly"}, current) do
    shift_months(current, 12)
  end

  defp next_date(%Event{recurrence_type: "every_n_days", recurrence_interval: n}, current) do
    Date.add(current, n)
  end

  defp next_date(%Event{recurrence_type: "every_n_weeks", recurrence_interval: n}, current) do
    Date.add(current, 7 * n)
  end

  defp next_date(%Event{recurrence_type: "every_n_months", recurrence_interval: n}, current) do
    shift_months(current, n)
  end

  defp shift_months(date, months) do
    total_months = date.year * 12 + (date.month - 1) + months
    year = div(total_months, 12)
    month = rem(total_months, 12) + 1
    day = min(date.day, Date.days_in_month(Date.new!(year, month, 1)))
    Date.new!(year, month, day)
  end
end
