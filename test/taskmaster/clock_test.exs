defmodule Taskmaster.ClockTest do
  @moduledoc """
  The board runs on one clock, Pacific, and `Taskmaster.Clock` is it.

  The dates below are the two 2026 switchovers — 8 March and 1 November — which
  is where anything hand-rolling an offset goes wrong.
  """

  use ExUnit.Case, async: true

  alias Taskmaster.Clock

  defp local(naive), do: naive |> Clock.to_local() |> DateTime.to_naive()
  defp abbr(naive), do: naive |> Clock.to_local() |> Map.fetch!(:zone_abbr)

  describe "the zone" do
    test "is Pacific" do
      assert Clock.timezone() == "America/Los_Angeles"
    end

    test "today is read off the Pacific clock, not the UTC one" do
      assert Clock.today() == DateTime.to_date(Clock.now())

      # Pacific is behind UTC all year, so the two agree until 16:00 or 17:00
      # local and differ by exactly one day after it. Any other answer means
      # `today/0` is reading the wrong clock.
      assert Date.diff(Date.utc_today(), Clock.today()) in [0, 1]
    end

    test "the date and the time of day come off one instant" do
      {date, time} = Clock.today_and_time()

      assert %Date{} = date
      assert %Time{microsecond: {0, 0}} = time
    end
  end

  describe "a stored UTC timestamp" do
    test "is read in standard time in winter" do
      assert local(~N[2026-01-05 03:15:00]) == ~N[2026-01-04 19:15:00]
      assert abbr(~N[2026-01-05 03:15:00]) == "PST"
    end

    test "is read in daylight time in summer" do
      assert local(~N[2026-07-05 03:15:00]) == ~N[2026-07-04 20:15:00]
      assert abbr(~N[2026-07-05 03:15:00]) == "PDT"
    end

    test "follows the spring-forward switchover" do
      assert local(~N[2026-03-08 09:59:00]) == ~N[2026-03-08 01:59:00]
      assert local(~N[2026-03-08 10:00:00]) == ~N[2026-03-08 03:00:00]
    end

    test "follows the fall-back switchover" do
      assert local(~N[2026-11-01 08:59:00]) == ~N[2026-11-01 01:59:00]
      assert local(~N[2026-11-01 09:00:00]) == ~N[2026-11-01 01:00:00]
    end
  end

  describe "formatting" do
    test "a time reads as a person says it" do
      assert Clock.format_time(~T[09:00:00]) == "9:00 AM"
      assert Clock.format_time(~T[13:05:00]) == "1:05 PM"
      assert Clock.format_time(~T[00:00:00]) == "12:00 AM"
      assert Clock.format_time(nil) == nil
    end

    test "the short form drops a zero minute, for the month grid" do
      assert Clock.format_time_short(~T[09:00:00]) == "9am"
      assert Clock.format_time_short(~T[13:30:00]) == "1:30pm"
      assert Clock.format_time_short(nil) == nil
    end

    test "a timestamp is rendered in Pacific, not as stored" do
      assert Clock.format_datetime(~N[2026-07-05 03:15:00]) == "Jul 04, 2026 8:15 PM"
      assert Clock.format_datetime(nil) == nil
    end

    test "a date carries its time only when it has one" do
      assert Clock.format_date_time(~D[2026-09-21], nil) == "Sep 21, 2026"
      assert Clock.format_date_time(~D[2026-09-21], ~T[09:05:00]) == "Sep 21, 2026 9:05 AM"
    end
  end

  describe "the rest of the app" do
    # The whole point of this module is that nothing else asks UTC what day or
    # what time it is. One `Date.utc_today/0` left in a handler is a board that
    # jumps a day every evening, which is exactly the kind of bug that gets
    # reported as "the calendar is sometimes wrong".
    test "never reads the wall clock from UTC" do
      # `NaiveDateTime.utc_now/0` is deliberately not in here: machine-written
      # timestamps stay UTC and are converted on the way out.
      wrong_clock = ~r/(?<![A-Za-z])(Date\.utc_today|Time\.utc_now)\(/

      offenders =
        for path <- Path.wildcard("lib/**/*.ex"),
            path != "lib/taskmaster/clock.ex",
            {line, number} <- Enum.with_index(File.stream!(path), 1),
            Regex.match?(wrong_clock, line),
            do: "#{path}:#{number}"

      assert offenders == []
    end
  end
end
