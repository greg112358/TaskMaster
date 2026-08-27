# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A family chore/calendar board: a **wall-mounted touchscreen appliance**, not a web app. It runs as an Elixir Desktop (wxWebView) window on a Raspberry Pi with an always-on microphone. `requirements.md` is the product spec, `stack.md` the target hardware, `instructions.md` a standing instruction to document work as you go.

Two constraints from the spec drive most UI decisions:

- **Readable from ~10 feet.** Big type and big hit targets throughout (`text-xl`+, `btn-lg`, `select-lg`). Don't add small text.
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

The HTTP port is `0` (random). To reach the app from a browser instead of the wx window, run `iex -S mix` and evaluate `TaskmasterWeb.Endpoint.url()`.

## Architecture

### Migrations are code, not files

`priv/repo/migrations/` is empty by design. Migrations are modules under `lib/taskmaster/repo/migrations/`, listed with explicit version numbers in `Taskmaster.Repo.Migrator`, and run by `Taskmaster.Application.start/2` at boot — a desktop app has no `mix ecto.migrate` available on the Pi. **A new migration must be added to that list or it never runs.** `mix ecto.migrate` is a no-op here.

`Application.start/2` also sets the SQLite path at runtime (`~/.config/taskmaster/taskmaster.db`) with `Keyword.put_new`, so a database configured in `config/*.exs` wins.

### One LiveView, presentational components

The router has exactly one route: `live "/", AppLive`. `TaskmasterWeb.AppLive` owns **all** application state and **all** `handle_event` clauses.

`GroceryLive`, `ChoreListLive` and `SettingsLive` are live_components with no `handle_event` at all — their buttons omit `phx-target`, so clicks bubble straight to `AppLive`. Follow that pattern; don't add local state to them.

`CalendarLive` is the deliberate exception, because month/week mode, the displayed month and the add-event modal are view state nobody else needs. It uses `phx-target={@myself}` for those, but hands actual writes back to the parent with `send(self(), {:add_event_from_form, params})`. Parent→child navigation goes the other way via `send_update(CalendarLive, id: "calendar", action: :prev)`.

### Contexts broadcast; AppLive reloads

Every write in `Taskmaster.People` / `Grocery` / `Events` ends with `tap(fn {:ok, _} -> broadcast() ...)` on its own PubSub topic. `AppLive` subscribes to all of them in `mount/3` and re-runs the list query when the message arrives.

So: **write through the context and let the broadcast update the UI.** Don't `assign/3` changed records directly — you'll desync any other subscriber (including the alert scheduler).

### Recurrence is computed, never materialized

An event is one row holding a rule (`recurrence_type` + `recurrence_interval` + optional `recurrence_day_of_week`). `Taskmaster.Events.Recurrence.occurrences_in_range/3` streams dates forward from `start_date`; there is never a row per occurrence. "Does this event fall on this day?" is always `occurrences_in_range(event, date, date) != []`.

Two things to know: it iterates from `start_date` each call, so a long-running daily rule costs one step per elapsed day; and `next_date/2` has no fallback clause, so an unrecognised `recurrence_type` raises rather than being ignored.

Everything is **dates, no times, no timezones** — `Date.utc_today()` throughout.

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

### Alerts

The chime-and-read-aloud checkbox has its own reference doc: **`docs/alerts.md`** — read it before touching `Taskmaster.Events.Alerts`, `AlertScheduler`, or `assets/js/chime.js`.

## Test environment

`config/test.exs` deviates from the defaults in ways that matter:

- The test database is a **file**, not `:memory:`. In-memory SQLite forces `pool_size: 1`, and the boot-time embedded migrations (which Ecto runs from a `Task`) deadlock a single-connection pool.
- `desktop_window: false` and `alert_scheduler: false` keep the wx window and the background poller out of the suite. Tests that need a scheduler start their own with a controlled `:tick_interval`.

`DataCase`/`ConnCase` run in shared sandbox mode unless a test is `async`, so spawned processes get database access without an explicit `allow`.

## Stack notes

Phoenix 1.8 + LiveView 1.1, Ecto with SQLite (`ecto_sqlite3`), Bandit, Tailwind 4 + daisyUI 5 (vendored under `assets/vendor/`), `desktop ~> 1.5`. Sessions are stored in an ETS table created in `Application.start/2`, not a cookie store.
