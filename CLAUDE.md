# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A family chore/calendar board: a **wall-mounted touchscreen appliance**. It runs two ways from one codebase — an Elixir Desktop (wx) window on the machine itself, or headless as a **web app** serving a wall-mounted Android tablet (`TASKMASTER_WEB=1`; see `docs/deployment.md`). Web app on a tablet is the current target. `requirements.md` is the product spec, `instructions.md` a standing instruction to document work as you go. `stack.md` still describes the older Raspberry Pi plan and is stale on the display half.

Two constraints from the spec drive most UI decisions:

- **Readable from ~10 feet.** Big type and big hit targets throughout (`text-xl`+, `btn-lg`, `select-lg`). Don't add small text. Two deliberate exceptions, both sizing in two steps — the bare class is a phone in portrait, `sm:` (640px up, so every tablet) is the board sizing: `GroceryLive`, where three columns share ~105px each, and `AppLive`'s bottom nav, where four labels share the width. A tablet renders identically either way, so don't "fix" the small bare classes in those two places.
- **Everything works by touch *and* by voice**, and the available voice commands are visible on screen (`AppLive.voice_hints/1`).

## Commands

```bash
mix setup                     # deps + db + assets, first time
mix precommit                 # the gate: compile --warnings-as-errors, deps.unlock --unused, format, test
mix test
mix test test/path/file.exs:42
mix assets.build              # tailwind + esbuild into priv/static
iex -S mix                    # runs the app; opens the desktop window
```

In the default desktop mode the HTTP port is `0` (random) — to reach it from a browser, evaluate `TaskmasterWeb.Endpoint.url()` in the IEx session. `TASKMASTER_WEB=1 PORT=4000 mix run --no-halt` instead binds `0.0.0.0:4000` with no wx window, which is how the tablet reaches it. Production runs as a systemd-managed release; `docs/deployment.md` has the full picture.

## Architecture

### Migrations are code, not files

`priv/repo/migrations/` is empty by design. Migrations are modules under `lib/taskmaster/repo/migrations/`, listed with explicit version numbers in `Taskmaster.Repo.Migrator`, and run by `Taskmaster.Application.start/2` at boot — a desktop app has no `mix ecto.migrate` available on the Pi. **A new migration must be added to that list or it never runs.** `mix ecto.migrate` is a no-op here.

`Application.start/2` also sets the SQLite path at runtime (`~/.config/taskmaster/taskmaster.db`) with `Keyword.put_new`, so a database configured in `config/*.exs` wins.

### One LiveView, presentational components

The wall board is one route: `live "/", AppLive`. `TaskmasterWeb.AppLive` owns **all** application state and **all** `handle_event` clauses for it.

(`/wkuk` is a second front end on the same release — a sketch ranking board for a phone or a desktop, not for the appliance. It has its own LiveViews, its own sizing rules and its own tables, and shares only the login. **`docs/wkuk.md`**.)

`ChoreListLive` and `SettingsLive` are live_components with no `handle_event` at all — their buttons omit `phx-target`, so clicks bubble straight to `AppLive`. Follow that pattern; don't add local state to them.

`GroceryLive` is the deliberate exception, because the typed query, the suggestion list and its modals are state nobody outside that screen needs. It uses `phx-target={@myself}` for that, but hands actual writes back to the parent with `send(self(), ...)`.

`CalendarLive` holds the two assigns in the same spirit — which view, and which month — but has no `handle_event` either: they arrive as `send_update(CalendarLive, id: "calendar", action: :prev)` from `AppLive`, which handles the header buttons. The Add / Edit Event modal is **`AppLive`'s**, not the calendar's, because the chore list opens the same form; see `TaskmasterWeb.EventForm` and **`docs/events.md`**. Taps inside the calendar (`open_event_form` on a day, `edit_event` on an event) bubble straight up. They nest, which is fine: LiveView dispatches a click to the *closest* element carrying a binding, so a tap on an event does not also open the add form behind it.

### Contexts broadcast; AppLive reloads

Every write in `Taskmaster.People` / `Grocery` / `Events` ends with `tap(fn {:ok, _} -> broadcast() ...)` on its own PubSub topic. `AppLive` subscribes to all of them in `mount/3` and re-runs the list query when the message arrives.

Writes taking an id (`toggle_item/1`, `delete_item/1`, `mark_done/1`, `delete_event/1`) use `Repo.get/2` and answer `:error` for a row that has gone: two tablets share this board, so a row disappearing under a tap is ordinary use, not a crash. `AppLive.with_id/2` is the matching parse.

So: **write through the context and let the broadcast update the UI.** Don't `assign/3` changed records directly — you'll desync any other subscriber (including the alert scheduler).

### Events and chores are one table

An event and a chore differ by the `type` column and nothing else, which is why
the form can switch one into the other with nothing to migrate. Both live in
`events`, both can carry a time (`start_time`, null for all day), a person, a
recurrence rule and an alert. The Add / Edit modal is one form for both, owned
by `AppLive`. Reference doc: **`docs/events.md`** — read it before touching
`Taskmaster.Events`, `Taskmaster.Clock` or `TaskmasterWeb.EventForm`.

### Recurrence is computed, never materialized

An event is one row holding a rule (`recurrence_type` + `recurrence_interval` + optional `recurrence_day_of_week`). `Taskmaster.Events.Recurrence.occurrences_in_range/3` streams dates forward from `start_date`; there is never a row per occurrence. "Does this event fall on this day?" is always `occurrences_in_range(event, date, date) != []`.

Two things to know: it iterates from `start_date` each call, so a long-running daily rule costs one step per elapsed day; and `next_date/2` has no fallback clause, so an unrecognised `recurrence_type` raises rather than being ignored.

The streams terminate **only while `next_date/2` strictly advances**, so `Event.changeset/2` validates `recurrence_type` against `Event.recurrence_types/0` and requires a positive `recurrence_interval` for the `every_n_*` rules; the `every_n_*` heads carry `n > 0` guards as well. An interval of zero once meant an endless stream on every render — a board that could not be recovered from its own screen. Any new rule has to advance.

Recurrence is **dates only**. An event's `start_time` rides along on the row and never enters the stream.

### Everything is Pacific, and `Taskmaster.Clock` is the only clock

The board is one appliance on one wall, so it has one time zone:
`America/Los_Angeles`, from the `tz` package compiled in at build time
(Elixir's own database is UTC-only and would raise on the name).

**Nothing in `lib/` may call `Date.utc_today/0` or `Time.utc_now/0`** — use
`Clock.today/0`, `Clock.time/0`, `Clock.today_and_time/0`.
`test/taskmaster/clock_test.exs` greps for the banned two and fails. Pacific is
7–8 hours behind UTC, so from late afternoon until midnight UTC is already on
tomorrow: a board reading UTC moves the "today" highlight, fires tomorrow's
alerts and dates a spoken "add task" a day early, every evening.

What a person types stays a wall clock: `start_date` and `start_time` are
Pacific and carry no offset, because a rule ("every 2 weeks at 9:00") has no
instant to attach one to. What the machine writes — `last_completed_at`, the
`timestamps()` pair — stays **UTC** and is converted on the way out by
`Clock.format_datetime/1`, never on the way in. Full detail, including the
formatting helpers and which column is in which zone, in **`docs/events.md`**.

### Audio and mic are behind one flag, and it is off

`Taskmaster.Audio.enabled?/0` gates **everything that uses the microphone or the
speakers** — speech recognition, speech synthesis, the alert chime, and the
`AlertScheduler` that drives it. It reads `config :taskmaster, :audio`, which
`config/config.exs` sets to `false`; `TASKMASTER_AUDIO=1` turns it back on
without a rebuild. The test env sets `audio: true` so the suite keeps covering
those features.

The gate is applied in four places, and a new audio feature needs the same
treatment:

- `Application.start/2` — no `AlertScheduler` child.
- `AppLive.mount/3` — reads it once into `@audio`, skips `Alerts.subscribe()`,
  and passes `audio={@audio}` to `CalendarLive` and `ChoreListLive`.
- `AppLive.render/1` — `phx-hook="VoiceRecognition"` is **not emitted**. That is
  the load-bearing half: the hook is what constructs the `SpeechRecognition`,
  the `AudioContext` and the utterances, so with no hook the page never asks for
  the microphone and cannot make a sound. The voice hint bar goes with it.
- The alert UI — the checkbox, its Test button and the 🔔 markers are `:if={@audio}`.

Speech out goes through `AppLive.speak/2`, which pushes nothing when the flag is
off. Nothing was deleted: the `alert` column, `Parser`, `chime.js` and the hook
are all still there, and the sections below describe them as they behave with
the flag on.

### Voice

`Taskmaster.Voice.Parser.parse/1` is a regex `cond` returning tagged tuples (`{:add_task, details}`, `{:navigate, view}`, `:unrecognized`, …) consumed by `AppLive`'s `"voice_command"` handler. **Clause order matters** — recurring patterns are matched before the catch-all one-time patterns.

Per spec, anything unparsed answers "I missed that", spoken via `push_event("speak", ...)` to the `VoiceRecognition` hook. That hook (`assets/js/hooks/voice_recognition.js`) owns both recognition and speech, restarts recognition continuously, and **mutes the mic while the app is talking** so read-aloud text isn't heard back as a command.

### Where speech actually works

Recognition and synthesis have very different support, and this constrains what
the voice half of the product can be:

| Runtime | `SpeechRecognition` (in) | `speechSynthesis` (out) |
| --- | --- | --- |
| Chrome / Samsung Internet on Android | yes (cloud, needs internet) | yes |
| **Android WebView** | **no** — Blink exposes the API but WebView never implemented the backend | yes (Android TTS) |
| Chrome on Linux/Pi | yes | only via **speech-dispatcher**, often not installed |
| Firefox (any platform) | no (off behind a flag on desktop) | yes |

Two consequences worth knowing before debugging: an embedded WebView cannot do
voice input no matter which browser is installed on the device, and
`speechSynthesis.speak()` is a **silent no-op** where no voices exist rather
than throwing — which is why the hook checks `getVoices()` and pushes
`speech_unavailable` to `AppLive` for on-screen display.

### Every page is behind one shared login

`TaskmasterWeb.Plugs.Auth` gates the `:browser` pipeline against `credentials.txt` (gitignored, one line `username:password`). No file means **no page is served at all** — a setup page replaces every response. Entry is basic auth; a signed ten-year cookie holding a fingerprint of the credentials is what avoids re-prompting, and editing the file invalidates it. The socket can't see the header, so the plug also puts the fingerprint in the session and `AppLive.mount/3` checks it.

Tests: `ConnCase` hands out an **authenticated** conn by default (fixture at `test/support/credentials.txt`, pointed at by `config/test.exs`); tests about auth build their own with `Phoenix.ConnTest.build_conn/0`. Details in `docs/deployment.md`.

### Groceries are categorised by an editable dictionary

Which of the three lists an item lands on comes from the `grocery_terms` table, not from code. It is seeded from `Taskmaster.Grocery.DefaultTerms` by migration 5 and edited from the screen thereafter, so **editing `DefaultTerms` does nothing to an existing database**. Matching is exact-then-longest-substring, so "whole milk" resolves via "milk" and "corned beef" beats "corn".

Two ways to file a word, and both write twice: the "which list?" dialog and dragging a row onto another column each move/add the item **and** `Dictionary.learn/2` the word. Moving only the row would put the next one straight back where the dictionary thought it went. The drag itself is `assets/js/hooks/grocery_drag.js` — one hook on the grid, horizontal-only so `touch-action: pan-y` can leave vertical scrolling to the browser and so it cannot race the `LongPress` on the same row.

The one ordering trap: after handing a dictionary write up to `AppLive`, a component must **not** recompute suggestions itself — that runs before the write. `Dictionary` broadcasts `:dictionary_changed` and the component refreshes on that. Full detail in **`docs/grocery-dictionary.md`**.

### Browser capabilities fail silently — report them

`speechSynthesis.speak()` with no voices installed does nothing at all, and
`navigator.wakeLock` is simply `undefined` outside a secure context. On a board
with no keyboard that is indistinguishable from a bug in the app.

So hooks push `device_warning` (`%{"key" => ..., "message" => ...}`) to
`AppLive`, which keys them in `@device_warnings` and renders them in the status
bar; a `nil` message clears that key. **Add new capability checks through that
channel** rather than adding another assign.

### Alerts

The chime-and-read-aloud checkbox has its own reference doc: **`docs/alerts.md`** — read it before touching `Taskmaster.Events.Alerts`, `AlertScheduler`, or `assets/js/chime.js`. An event carrying a `start_time` announces at that time; an all-day one on the first poll of its day, both on the Pacific clock.

### The sketch ranking board

`/wkuk` ranks all 384 Whitest Kids U' Know sketches into S–F tiers, one board per
person, by dragging rows and tier bars. A sketch's tier is never stored — it is
read off the nearest bar above it, which is what makes the bars worth dragging.
Reference doc: **`docs/wkuk.md`**. Read it before touching `Taskmaster.Wkuk`,
`TaskmasterWeb.WkukBoardLive`, or `assets/js/hooks/wkuk_drag.js`.

## Test environment

`config/test.exs` deviates from the defaults in ways that matter:

- The test database is a **file**, not `:memory:`. In-memory SQLite forces `pool_size: 1`, and the boot-time embedded migrations (which Ecto runs from a `Task`) deadlock a single-connection pool.
- `desktop_window: false` and `alert_scheduler: false` keep the wx window and the background poller out of the suite. Tests that need a scheduler start their own with a controlled `:tick_interval`.

`DataCase`/`ConnCase` run in shared sandbox mode unless a test is `async`, so spawned processes get database access without an explicit `allow`.

SQLite runs in **WAL** mode (`config/config.exs`) — without it, a reader arriving mid-write fails outright with "database is locked". Expect a few such errors on the *first* boot against a new database file, while the pool opens alongside the embedded migrations; every boot after that is clean.

Transactions are `:immediate` (`BEGIN IMMEDIATE`). A deferred transaction starts as a reader and takes the write lock at its first write; if another connection got there first, SQLite returns SQLITE_BUSY **immediately and ignores `busy_timeout`**, because waiting could deadlock. Taking the lock up front is what makes `busy_timeout` apply at all.

Two test-only deviations, both load-bearing: `journal_mode: :delete`, and `pool_size: 2` — the minimum, since Ecto always runs a migration in a Task while the caller holds a connection.

**No test waits on a clock.** The suite has no `Process.sleep`, and the alert
refutations use `refute_received` (no timeout) after a `:sys.get_state/1` barrier
on the scheduler, not `refute_receive ..., 200`. A synchronous system message is
answered only after everything already queued, and PubSub delivers to a local
subscriber with a plain `send` before the write returns — so once the barrier
comes back, any alert is already in the test's mailbox. That is a stronger
assertion than a timeout, not a weaker one, and it was 500ms of a 1.2s suite.
Don't reintroduce a timeout to "fix" a flake there; find the missing barrier.

**LiveView tests must call `isolate_view/1`** (in `ConnCase`) on every mounted view. `live/2` links the view to the test process, so it dies exactly as the test ends and a message still in flight can write while the *next* test owns the connection — an intermittent "Database busy" in an unrelated test. `isolate_view/1` unlinks and stops it synchronously in an `on_exit` that LIFO puts before the sandbox's.

Tests touching the dictionary must also let its PubSub round trip drain before asserting on the DOM — see `settle/1` in `grocery_dictionary_test.exs`.

## Copy

Every user-facing string — status bar, errors, labels, empty states, device
warnings — follows the `deslop` skill (`.claude/skills/deslop/`): terse,
technical, no fluff, name the field and the value. Rejected writes go through
`AppLive.error_message/1`, which renders `Invalid field: name="Greg" (has already
been taken)` or `Missing field: title`; device warnings name the web API
(`wakeLock: needs https`). Read it before adding a string.

The two deliberate exceptions are `I missed that` for unparsed speech, which
`requirements.md` mandates, and `Alerts.announcement/1`, which is spoken to a
family rather than read off a screen.

## Known failure patterns

Nine patterns that have already produced bugs here — DOM-only form state,
non-terminating recurrence streams, raising conversions on client input, broadcast
feedback loops — with a running list of every instance found and its status. In the
`bug-patterns` skill (`.claude/skills/bug-patterns/`). Read it before fixing a bug
or reviewing a diff, and append to `findings.md` when you find or fix one.

## Stack notes

Phoenix 1.8 + LiveView 1.1, Ecto with SQLite (`ecto_sqlite3`), Bandit, Tailwind 4 + daisyUI 5 (vendored under `assets/vendor/`), `desktop ~> 1.5`, `tz` for the IANA time zone rules (see `Taskmaster.Clock`). Sessions are stored in an ETS table created in `Application.start/2`, not a cookie store.
