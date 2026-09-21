defmodule Taskmaster.Voice.Parser do
  @moduledoc """
  Turns a spoken sentence into a tagged tuple for `TaskmasterWeb.AppLive`.

  A `cond` of regexes, and **clause order matters**: the recurring patterns are
  matched before the catch-all one-time ones.

  ## Times

  Anything that ends in a time of day — "add event dentist at 3pm", "add task
  bins at 7:30 am every week" — carries a `:start_time` and loses that phrase
  from the title. Recognised: `3pm`, `3:30 pm`, `noon`, `midnight`, and a
  24-hour `14:30`.

  A bare `at 7:30` is **not** a time, and stays in the title as typed. Half
  past seven in the morning and half past seven in the evening are equally
  likely on a family board, and a spoken time that means either is better left
  visible than guessed at — the recogniser writes "7:30 PM" whenever the
  speaker actually said one.
  """

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
        {title, start_time} = split_time(String.trim(Enum.at(match, 1)))
        {:add_event, %{title: title, start_time: start_time}}

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
    person_name = blank_to_nil(Enum.at(match, 1))
    {title, start_time} = split_time(String.trim(Enum.at(match, 2)))
    recurrence_text = Enum.at(match, 3)
    {rec_type, rec_interval, rec_dow} = parse_recurrence(recurrence_text)

    {:add_task,
     %{
       title: title,
       start_time: start_time,
       person_name: person_name,
       recurrence_type: rec_type,
       recurrence_interval: rec_interval,
       recurrence_day_of_week: rec_dow
     }}
  end

  defp parse_one_time_task(match) do
    person_name = blank_to_nil(Enum.at(match, 1))
    {title, start_time} = split_time(String.trim(Enum.at(match, 2)))

    {:add_task,
     %{
       title: title,
       start_time: start_time,
       person_name: person_name,
       recurrence_type: nil,
       recurrence_interval: nil,
       recurrence_day_of_week: nil
     }}
  end

  defp parse_event(match) do
    {title, start_time} = split_time(String.trim(Enum.at(match, 1)))
    recurrence_text = Enum.at(match, 2)
    {rec_type, rec_interval, rec_dow} = parse_recurrence(recurrence_text)

    {:add_event,
     %{
       title: title,
       start_time: start_time,
       recurrence_type: rec_type,
       recurrence_interval: rec_interval,
       recurrence_day_of_week: rec_dow
     }}
  end

  # An optional capture group that did not participate is "", not nil, and ""
  # is truthy — read as a name, it sends "add task vacuum" down the "Unknown
  # person:" path instead of adding the task.
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # A trailing time of day, split off the title it was spoken with. The whole
  # phrase stays in the title when it is not a time this understands, so a
  # guess is never stored in place of what was said.
  @time_phrase ~r/^(?<title>.+?)\s+at\s+(?<time>\d{1,2}(?::\d{2})?\s*[ap]\.?m\.?|noon|midnight|\d{1,2}:\d{2})$/

  defp split_time(title) do
    with %{"title" => stripped, "time" => time_text} <-
           Regex.named_captures(@time_phrase, title),
         %Time{} = time <- parse_time(time_text) do
      {String.trim(stripped), time}
    else
      _no_time -> {title, nil}
    end
  end

  defp parse_time("noon"), do: ~T[12:00:00]
  defp parse_time("midnight"), do: ~T[00:00:00]

  # `named_captures` rather than `run`: a group that did not participate is ""
  # here, where `run` simply drops the trailing ones and leaves a list of
  # whatever length the input happened to produce.
  @time_parts ~r/^(?<hour>\d{1,2})(?::(?<minute>\d{2}))?\s*(?<meridiem>am|pm)?$/

  defp parse_time(text) do
    case Regex.named_captures(@time_parts, String.replace(text, ".", "")) do
      %{"hour" => hour, "minute" => minute, "meridiem" => meridiem} ->
        build_time(String.to_integer(hour), minute, meridiem)

      nil ->
        nil
    end
  end

  defp build_time(hour, minute, meridiem) do
    minute = if minute == "", do: 0, else: String.to_integer(minute)

    hour =
      case {meridiem, hour} do
        {"am", 12} -> 0
        {"am", hour} -> hour
        {"pm", hour} when hour < 12 -> hour + 12
        {"pm", hour} -> hour
        # No am/pm. Only a 24-hour reading is unambiguous; "at 7:30" is not one
        # and is refused here, which leaves the phrase in the title.
        {"", hour} when hour > 12 -> hour
        {"", _hour} -> nil
      end

    with hour when is_integer(hour) <- hour,
         {:ok, time} <- Time.new(hour, minute, 0) do
      time
    else
      _invalid -> nil
    end
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
