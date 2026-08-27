# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A family chore/calendar board: a **wall-mounted touchscreen appliance**. It runs two ways from one codebase — an Elixir Desktop (wx) window on the machine itself, or headless as a **web app** serving a wall-mounted Android tablet (`TASKMASTER_WEB=1`; see `docs/deployment.md`). Web app on a tablet is the current target. `requirements.md` is the product spec, `instructions.md` a standing instruction to document work as you go. `stack.md` still describes the older Raspberry Pi plan and is stale on the display half.

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

In the default desktop mode the HTTP port is `0` (random) — to reach it from a browser, evaluate `TaskmasterWeb.Endpoint.url()` in the IEx session. `TASKMASTER_WEB=1 PORT=4000 mix run --no-halt` instead binds `0.0.0.0:4000` with no wx window, which is how the tablet reaches it. Production runs as a systemd-managed release; `docs/deployment.md` has the full picture.

## Architecture

### Migrations are code, not files

`priv/repo/migrations/` is empty by design. Migrations are modules under `lib/taskmaster/repo/migrations/`, listed with explicit version numbers in `Taskmaster.Repo.Migrator`, and run by `Taskmaster.Application.start/2` at boot — a desktop app has no `mix ecto.migrate` available on the Pi. **A new migration must be added to that list or it never runs.** `mix ecto.migrate` is a no-op here.

`Application.start/2` also sets the SQLite path at runtime (`~/.config/taskmaster/taskmaster.db`) with `Keyword.put_new`, so a database configured in `config/*.exs` wins.

### One LiveView, presentational components

The router has exactly one route: `live "/", AppLive`. `TaskmasterWeb.AppLive` owns **all** application state and **all** `handle_event` clauses.

`ChoreListLive` and `SettingsLive` are live_components with no `handle_event` at all — their buttons omit `phx-target`, so clicks bubble straight to `AppLive`. Follow that pattern; don't add local state to them.

`CalendarLive` and `GroceryLive` are the deliberate exceptions, because view mode, the displayed month, the typed query, the suggestion list and the modals are state nobody outside those screens needs. They use `phx-target={@myself}` for that, but hand actual writes back to the parent with `send(self(), ...)`. Parent→child messages go the other way via `send_update(CalendarLive, id: "calendar", action: :prev)`.

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

### Every page is behind one shared login

`TaskmasterWeb.Plugs.Auth` gates the `:browser` pipeline against `credentials.txt` (gitignored, one line `username:password`). No file means **no page is served at all** — a setup page replaces every response. Entry is basic auth; a signed ten-year cookie holding a fingerprint of the credentials is what avoids re-prompting, and editing the file invalidates it. The socket can't see the header, so the plug also puts the fingerprint in the session and `AppLive.mount/3` checks it.

Tests: `ConnCase` hands out an **authenticated** conn by default (fixture at `test/support/credentials.txt`, pointed at by `config/test.exs`); tests about auth build their own with `Phoenix.ConnTest.build_conn/0`. Details in `docs/deployment.md`.

### Groceries are categorised by an editable dictionary

Which of the three lists an item lands on comes from the `grocery_terms` table, not from code. It is seeded from `Taskmaster.Grocery.DefaultTerms` by migration 5 and edited from the screen thereafter, so **editing `DefaultTerms` does nothing to an existing database**. Matching is exact-then-longest-substring, so "whole milk" resolves via "milk" and "corned beef" beats "corn".

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

The chime-and-read-aloud checkbox has its own reference doc: **`docs/alerts.md`** — read it before touching `Taskmaster.Events.Alerts`, `AlertScheduler`, or `assets/js/chime.js`.

## Test environment

`config/test.exs` deviates from the defaults in ways that matter:

- The test database is a **file**, not `:memory:`. In-memory SQLite forces `pool_size: 1`, and the boot-time embedded migrations (which Ecto runs from a `Task`) deadlock a single-connection pool.
- `desktop_window: false` and `alert_scheduler: false` keep the wx window and the background poller out of the suite. Tests that need a scheduler start their own with a controlled `:tick_interval`.

`DataCase`/`ConnCase` run in shared sandbox mode unless a test is `async`, so spawned processes get database access without an explicit `allow`.

SQLite runs in **WAL** mode (`config/config.exs`) — without it, a reader arriving mid-write fails outright with "database is locked". Expect a few such errors on the *first* boot against a new database file, while the pool opens alongside the embedded migrations; every boot after that is clean.

Transactions are `:immediate` (`BEGIN IMMEDIATE`). A deferred transaction starts as a reader and takes the write lock at its first write; if another connection got there first, SQLite returns SQLITE_BUSY **immediately and ignores `busy_timeout`**, because waiting could deadlock. Taking the lock up front is what makes `busy_timeout` apply at all.

Two test-only deviations, both load-bearing: `journal_mode: :delete`, and `pool_size: 2` — the minimum, since Ecto always runs a migration in a Task while the caller holds a connection.

**LiveView tests must call `isolate_view/1`** (in `ConnCase`) on every mounted view. `live/2` links the view to the test process, so it dies exactly as the test ends and a message still in flight can write while the *next* test owns the connection — an intermittent "Database busy" in an unrelated test. `isolate_view/1` unlinks and stops it synchronously in an `on_exit` that LIFO puts before the sandbox's.

Tests touching the dictionary must also let its PubSub round trip drain before asserting on the DOM — see `settle/1` in `grocery_dictionary_test.exs`.

## Stack notes

Phoenix 1.8 + LiveView 1.1, Ecto with SQLite (`ecto_sqlite3`), Bandit, Tailwind 4 + daisyUI 5 (vendored under `assets/vendor/`), `desktop ~> 1.5`. Sessions are stored in an ETS table created in `Application.start/2`, not a cookie store.
