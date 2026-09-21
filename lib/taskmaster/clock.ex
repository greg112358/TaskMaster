defmodule Taskmaster.Clock do
  @moduledoc """
  The board's clock. **Every date and time a person sees or types is Pacific.**

  The board is one appliance on one wall in one house, so it has one time zone
  and no per-user setting. `Date.utc_today/0` is wrong here for the obvious
  reason: after 4pm Pacific (5pm in winter) UTC has already rolled into
  tomorrow, so a board asking UTC for "today" would move the highlight, fire
  today's alerts and file a spoken "add task" a day early, every single evening.
  Nothing in `lib/` may call `Date.utc_today/0` or `Time.utc_now/0`; call
  `today/0` and `time/0` here instead.

  ## What is stored, and in which zone

  | Column | Zone |
  | --- | --- |
  | `events.start_date`, `events.start_time` | Pacific wall clock, as typed |
  | `events.last_alerted_on` | Pacific date |
  | `events.last_completed_at`, `inserted_at`, `updated_at` | UTC |

  An event's date and time are what the wall clock will read when it happens —
  9:00 means 9:00 in March and in December alike, which is what a person means
  by "school run at 9". There is deliberately no offset stored with it: a rule
  ("every 2 weeks at 9:00") has no single instant to attach one to.

  Timestamps written by the machine stay UTC, the format `NaiveDateTime.utc_now/0`
  produces and every existing row already holds. They are converted on the way
  out (`format_datetime/1`), never on the way in — a fall-back DST hour would
  otherwise be ambiguous and unorderable.

  The IANA rules come from the `tz` package, compiled in (see `config/config.exs`).
  Elixir's built-in database is UTC-only and would raise on the zone name.
  """

  @zone "America/Los_Angeles"

  @doc "The one zone this board runs in."
  def timezone, do: @zone

  @doc "Now, Pacific."
  def now, do: DateTime.now!(@zone)

  @doc "Today's date, Pacific. The replacement for `Date.utc_today/0`."
  def today, do: now() |> DateTime.to_date()

  @doc "The current wall-clock time, Pacific, to the second."
  def time, do: now() |> DateTime.to_time() |> Time.truncate(:second)

  @doc """
  Today's date and the current time of day, read off one instant.

  Two separate calls to `today/0` and `time/0` can straddle midnight and pair
  yesterday's date with today's 00:00.
  """
  def today_and_time do
    now = now()
    {DateTime.to_date(now), now |> DateTime.to_time() |> Time.truncate(:second)}
  end

  @doc """
  A UTC timestamp out of the database as a Pacific `DateTime`.

  `last_completed_at` and the `timestamps()` pair are naive UTC; anything
  rendering one goes through here first.
  """
  def to_local(%NaiveDateTime{} = naive) do
    naive
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.shift_zone!(@zone)
  end

  def to_local(%DateTime{} = datetime), do: DateTime.shift_zone!(datetime, @zone)

  @doc ~S"""
  A time of day as a person reads it: `9:00 AM`. `nil` for an all-day row, which
  callers render as their own dash or empty string.

      iex> Taskmaster.Clock.format_time(~T[09:00:00])
      "9:00 AM"
  """
  def format_time(nil), do: nil
  def format_time(%Time{} = time), do: Calendar.strftime(time, "%-I:%M %p")

  @doc ~S"""
  The same time in the space a month-view cell has: `9am`, `9:30am`. The minutes
  are dropped when they are zero, because seven of these share the screen width.

      iex> Taskmaster.Clock.format_time_short(~T[09:00:00])
      "9am"
      iex> Taskmaster.Clock.format_time_short(~T[13:30:00])
      "1:30pm"
  """
  def format_time_short(nil), do: nil

  def format_time_short(%Time{minute: 0} = time), do: Calendar.strftime(time, "%-I%P")
  def format_time_short(%Time{} = time), do: Calendar.strftime(time, "%-I:%M%P")

  @doc "A date as `Sep 21, 2026`."
  def format_date(nil), do: nil
  def format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")

  @doc """
  A stored UTC timestamp as `Sep 21, 2026 9:00 AM`, Pacific.
  """
  def format_datetime(nil), do: nil

  def format_datetime(%NaiveDateTime{} = naive) do
    naive |> to_local() |> Calendar.strftime("%b %d, %Y %-I:%M %p")
  end

  @doc """
  A date and an optional time as one string: `Sep 21, 2026` or
  `Sep 21, 2026 9:00 AM`.
  """
  def format_date_time(nil, _time), do: nil
  def format_date_time(%Date{} = date, nil), do: format_date(date)

  def format_date_time(%Date{} = date, %Time{} = time) do
    "#{format_date(date)} #{format_time(time)}"
  end
end
