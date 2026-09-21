# Events, chores, times and the clock

One table, `events`, holds both halves of the board: an **event** is something
that happens ("Dentist"), a **task** — a chore — is something somebody has to do
("Vacuum"). The only difference between them is the `type` column, which is why
the form can switch one into the other and nothing has to move.

This document covers the row, the time on it, the Pacific clock the whole app
runs on, and the one modal that writes all of it. Read it before touching
`Taskmaster.Events`, `Taskmaster.Clock`, `TaskmasterWeb.EventForm` or the
`AppLive` handlers named below. Alerts have their own document,
[`alerts.md`](alerts.md); recurrence is summarised here and detailed in
CLAUDE.md.

---

## The row

| Column | Meaning |
| --- | --- |
| `title` | what it is called |
| `type` | `"event"` or `"task"`; `validate_inclusion` on write |
| `start_date` | the day it happens, or the day a recurrence starts |
| `start_time` | the wall-clock time it happens, or null for all day |
| `recurrence_type` / `_interval` / `_day_of_week` | the repeat rule, never materialised |
| `person_id` | who it belongs to, nullable |
| `alert` / `last_alerted_on` | the chime-and-read-aloud checkbox |
| `last_completed_at` | when a chore was last marked Done |

`start_time` arrived in migration 8. Migrations are embedded modules listed in
`Taskmaster.Repo.Migrator` — a new one must go in that list or it never runs.

### What the type actually changes

Nothing else in the row. Switching a chore to an event and back is lossless:

| | Event | Task |
| --- | --- | --- |
| Appears in `Events.list_tasks/0`, so on the Chores screen | no | yes |
| Colour on the calendar | `bg-info/30` | `bg-warning/30` |
| Spoken alert wording (`Alerts.announcement/1`) | "Today: Dentist" | "Time to vacuum" |
| Everything else — time, person, recurrence, alert, history | same | same |

`last_completed_at` is deliberately **not** cleared when a chore becomes an
event. It is history, the Chores screen is the only thing that reads it, and
keeping it means switching back restores the row exactly. Tests for the round
trip are in `test/taskmaster_web/live/event_edit_test.exs`.

---

## Times

`start_time` is a wall-clock time: 9:00 means 9:00 in January and in July
alike, which is what a person means by "school run at 9". There is no offset
stored beside it and no instant to attach one to — a rule like "every 2 weeks
at 9:00" does not have one.

* **Null is all day.** Not midnight. An all-day row sorts ahead of every timed
  one, shows no time, and alerts on the first poll of its day; a row at
  `00:00:00` is a timed row that happens to be at midnight.
* **Clearing the Time field is how you get back to all day.** The empty string
  casts to `nil` (Ecto's `:empty_values`).
* **Stored to the second.** `Event.changeset/2` truncates, because SQLite keeps
  a time as text and `"09:00:00.000000"` would order against `"09:00:00"` as a
  string.
* **Ordering.** `list_events/0` and `list_tasks/0` order by
  `start_date, start_time`; SQLite sorts NULL first ascending, which is the
  order a day should read in. `CalendarLive.events_for_date/2` re-sorts within
  a day, because a recurring row's `start_date` says nothing about where it
  falls *today*.
* **Recurrence ignores times entirely.** `Recurrence` streams dates; the time
  rides along on the row.

### Spoken times

`Taskmaster.Voice.Parser` splits a trailing time phrase off the title:

| Said | Title | `start_time` |
| --- | --- | --- |
| add event dentist at 3pm | dentist | 15:00 |
| add task bins at 7:30 am every week | bins | 07:30 |
| add task bins at noon / at midnight | bins | 12:00 / 00:00 |
| add event standup at 14:30 | standup | 14:30 |
| add event dinner **at 7:30** | dinner at 7:30 | — |
| add event meet greg at the park | meet greg at the park | — |

The last two are the rule worth keeping: a time that could mean either half of
the day is **left in the title** rather than guessed at. A recogniser writes
"7:30 PM" whenever the speaker actually said one, so a bare "7:30" carries no
information — and a wrong guess ends up stored, on the wall, to be found and
corrected later.

---

## The clock: everything is Pacific

`Taskmaster.Clock` is the only module that reads the wall clock.
`Date.utc_today/0` and `Time.utc_now/0` are banned everywhere else in `lib/`,
and `test/taskmaster/clock_test.exs` greps for them and fails.

The reason is mundane and the bug is not: Pacific is 7 or 8 hours behind UTC,
so from 4pm or 5pm local until midnight, UTC has already rolled into tomorrow.
A board asking UTC what day it is would move the "today" highlight, fire
tomorrow's alerts and file a spoken "add task" a day early — every evening,
and only in the evening.

```elixir
Clock.today()            # ~D[2026-09-21]  Pacific
Clock.time()             # ~T[14:25:11]    Pacific, to the second
Clock.today_and_time()   # both, off one instant — never straddles midnight
Clock.to_local(naive)    # a stored UTC timestamp as a Pacific DateTime
```

### Which zone a column is in

| Written by | Zone |
| --- | --- |
| A person: `start_date`, `start_time` | Pacific wall clock, as typed |
| The alert scheduler: `last_alerted_on` | Pacific date |
| The machine: `last_completed_at`, `inserted_at`, `updated_at` | UTC |

Machine timestamps stay UTC — that is what `NaiveDateTime.utc_now/0` produces
and what every existing row already holds — and are converted on the way out
(`Clock.format_datetime/1`), never on the way in. Storing them Pacific would
make the fall-back hour ambiguous and the column unorderable for an hour every
November.

### The IANA database

Elixir ships a UTC-only time zone database, so `DateTime.now!("America/Los_Angeles")`
would raise. The rules come from the `tz` package, compiled in at build time
and configured in `config/config.exs`:

```elixir
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
config :tz, reject_periods_before_year: 2020,
            build_dst_periods_until_year: 20 + NaiveDateTime.utc_now().year
```

Compiled rather than fetched, because the board has to boot correctly with no
network. `build_dst_periods_until_year` is pushed out to 20 years because a
release can sit unrebuilt for a long time on an appliance and a lookup past the
compiled range is computed the slow way. Changing either option needs
`mix deps.compile tz --force`.

The two switchovers are asserted directly in `clock_test.exs`, which is the
test to look at if anything ever looks an hour out.

### Formatting

| Function | Reads | Where |
| --- | --- | --- |
| `format_time/1` | `9:00 AM` | week view, chore list, status bar |
| `format_time_short/1` | `9am`, `1:30pm` | month grid, where seven cells share the width |
| `format_date/1` | `Sep 21, 2026` | chore list |
| `format_datetime/1` | `Jul 04, 2026 8:15 PM` | Last Done (converts from UTC) |
| `format_date_time/2` | date, plus the time when there is one | Next Due |

---

## The one form

`TaskmasterWeb.EventForm.event_form/1` is the Add **and** Edit modal. It is
markup only: **`AppLive` owns the state and every handler**, because both the
calendar and the chore list open it and `CalendarLive` cannot render a modal
for a screen it is not on.

```
CalendarLive  day cell        phx-click="open_event_form"  phx-value-date=…
CalendarLive  event chip      phx-click="edit_event"       phx-value-id=…
ChoreListLive Edit button     phx-click="edit_event"       phx-value-id=…
EventForm     the form        phx-change="event_form_changed"
                              phx-submit="save_event"
EventForm     Cancel / Delete phx-click="close_event_form" | "delete_event"
```

None of them carry `phx-target`, so every one bubbles to `AppLive`.

Two assigns hold the whole thing: `@event_form`, a map of **string** field
values (nil when the modal is closed), and `@event_form_id`, the id being
edited or nil for a new row.

* **Create or update is decided by `@event_form_id`, not by the form.** The id
  is in the form map because the Delete button needs it in a `phx-value-id`,
  but no input posts it and `save_event` never reads one: a server-owned
  identifier does not round-trip through a form (the shape of F13 in the
  bug-patterns log).
* **Every control renders `value=` / `checked=` / `selected=` from that map.**
  This is pattern P1: a control the server renders without a value is *erased*
  by the next LiveView patch, and showing or hiding the interval field is a
  patch. `merge_event_form/2` drops absent keys so a hidden field does not wipe
  its own stored value.
* **A rejected write keeps the form open** with what was typed, and names the
  field in the status bar through `AppLive.error_message/1`.
* **A stale id is not a crash.** Opening the form for a deleted row does
  nothing; saving into one answers `Unknown event: <id>` and closes. Two
  tablets share this board.
* **With audio off the alert checkbox is not rendered**, so the form sends no
  `alert` key — and `event_attrs/3` then leaves the column alone instead of
  reading the missing key as `false`. Editing a row on a silent board must not
  disarm it.

### Adding a field to the form

Five places, all in step:

1. the migration (a new module, listed in `Taskmaster.Repo.Migrator`),
2. `Event.schema` and the `cast` list,
3. `AppLive.blank_event_form/1` and `event_form_fields/1` — the string form of it,
4. `AppLive.event_attrs/3` — back out of the form, un-raising,
5. the markup in `EventForm`, rendering its value from the map.

The Frequency select is the one duplicated list: it hard-codes the same seven
rules as `Event.recurrence_types/0` because it needs a label for each. They are
compared at compile time in `event_form.ex`, so drift is a build failure.
