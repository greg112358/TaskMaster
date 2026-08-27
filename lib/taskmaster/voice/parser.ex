defmodule Taskmaster.Voice.Parser do
  def parse(transcript) do
    text = transcript |> String.trim() |> String.downcase()

    cond do
      match =
          Regex.run(~r/^show\s+(groceries|grocery|calendar|chores?|chore\s*list|settings)$/, text) ->
        {:navigate, normalize_view(Enum.at(match, 1))}

      match = Regex.run(~r/^add\s+(.+)\s+to\s+groceries$/, text) ->
        {:add_grocery, String.trim(Enum.at(match, 1))}

      Regex.match?(~r/^clear\s+groceries$/, text) ->
        :clear_groceries

      match =
          Regex.run(
            ~r/^add\s+(?:task|chore)\s+(?:for\s+(\w+)\s+)?(.+?)\s+(every\s+.+|annually|yearly|daily|weekly|monthly)$/i,
            text
          ) ->
        parse_task(match)

      match =
          Regex.run(
            ~r/^add\s+event\s+(.+?)\s+(every\s+.+|annually|yearly|daily|weekly|monthly)$/i,
            text
          ) ->
        parse_event(match)

      match = Regex.run(~r/^add\s+(?:task|chore)\s+(?:for\s+(\w+)\s+)?(.+)$/i, text) ->
        parse_one_time_task(match)

      match = Regex.run(~r/^add\s+event\s+(.+)$/i, text) ->
        {:add_event, %{title: String.trim(Enum.at(match, 1))}}

      true ->
        :unrecognized
    end
  end

  defp normalize_view(view) do
    case view do
      v when v in ["groceries", "grocery"] -> :groceries
      "calendar" -> :calendar
      v when v in ["chore", "chores", "chore list", "chorelist"] -> :chores
      "settings" -> :settings
      _ -> :calendar
    end
  end

  defp parse_task(match) do
    person_name = Enum.at(match, 1)
    title = String.trim(Enum.at(match, 2))
    recurrence_text = Enum.at(match, 3)
    {rec_type, rec_interval, rec_dow} = parse_recurrence(recurrence_text)

    {:add_task,
     %{
       title: title,
       person_name: person_name,
       recurrence_type: rec_type,
       recurrence_interval: rec_interval,
       recurrence_day_of_week: rec_dow
     }}
  end

  defp parse_one_time_task(match) do
    person_name = Enum.at(match, 1)
    title = String.trim(Enum.at(match, 2))

    {:add_task,
     %{
       title: title,
       person_name: person_name,
       recurrence_type: nil,
       recurrence_interval: nil,
       recurrence_day_of_week: nil
     }}
  end

  defp parse_event(match) do
    title = String.trim(Enum.at(match, 1))
    recurrence_text = Enum.at(match, 2)
    {rec_type, rec_interval, rec_dow} = parse_recurrence(recurrence_text)

    {:add_event,
     %{
       title: title,
       recurrence_type: rec_type,
       recurrence_interval: rec_interval,
       recurrence_day_of_week: rec_dow
     }}
  end

  defp parse_recurrence(text) do
    text = String.downcase(String.trim(text))

    cond do
      text in ["daily", "every day"] ->
        {"daily", 1, nil}

      text in ["weekly", "every week"] ->
        {"weekly", 1, nil}

      text in ["monthly", "every month", "once a month"] ->
        {"monthly", 1, nil}

      text in ["yearly", "annually", "every year", "once a year"] ->
        {"yearly", 1, nil}

      match = Regex.run(~r/every\s+(\w+)/, text) ->
        parse_every(Enum.at(match, 1), text)

      true ->
        {nil, nil, nil}
    end
  end

  defp parse_every(word, full_text) do
    day_of_week = day_name_to_number(word)

    cond do
      day_of_week ->
        {"weekly", 1, day_of_week}

      match = Regex.run(~r/every\s+(\d+)\s+(day|week|month)s?/, full_text) ->
        n = String.to_integer(Enum.at(match, 1))
        unit = Enum.at(match, 2)

        case unit do
          "day" -> {"every_n_days", n, nil}
          "week" -> {"every_n_weeks", n, nil}
          "month" -> {"every_n_months", n, nil}
        end

      true ->
        {nil, nil, nil}
    end
  end

  @days %{
    "sunday" => 7,
    "monday" => 1,
    "tuesday" => 2,
    "wednesday" => 3,
    "thursday" => 4,
    "friday" => 5,
    "saturday" => 6
  }

  defp day_name_to_number(name) do
    Map.get(@days, String.downcase(name))
  end
end
