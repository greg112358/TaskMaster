# Alerts (chime + read aloud)

The Add Event / Task form has a **🔔 Chime & read aloud when due** checkbox. An
event or task saved with it ticked announces itself on the day it is due: a
two-note chime, then the title read out by the speech synthesiser.

This document covers how that works end to end, what its timing guarantees are
(and are not), and where to hook in if you are extending it.

---

## User-facing behaviour

| Where | What you see |
| --- | --- |
| Add Event / Task modal | The checkbox, plus a **Test** button that chimes and reads the title you have typed so you can check the volume |
| Month and week calendar | A 🔔 in front of the title of any alerting event |
| Chore list | A 🔔 in front of the chore name |
| When an alert fires | The chime + speech, and the alert text in the status bar at the top of the screen |

The spoken sentence depends on the type and assignee:

| Event | Spoken |
| --- | --- |
| Task, nobody assigned | "Time to clean cat tree" |
| Task assigned to Greg | "Greg, time to clean cat tree" |
| Event, nobody assigned | "Today: Cat's Birthday" |
| Event assigned to Greg | "Today: Dentist, for Greg" |

The wording lives in one place — `Taskmaster.Events.Alerts.announcement/1`.

---

## Data model

Migration `4`, `Taskmaster.Repo.Migrations.AddAlertToEvents`, adds two columns
to `events`:

| Column | Type | Meaning |
| --- | --- | --- |
| `alert` | boolean, `false` | The checkbox. When true this event announces itself. |
| `last_alerted_on` | date, null | The day it last announced. |

`last_alerted_on` is what stops an alert repeating. It is a **date**, not a
timestamp, because the poll below runs continuously — without it a due alert
would fire every 30 seconds all day, and a restart would replay alerts that had
already been announced.

Migrations are embedded (there are no files in `priv/repo/migrations`), so a new
one must be added to the list in `Taskmaster.Repo.Migrator`. Existing databases
pick the new columns up on the next app start.

---

## The chain

```
Taskmaster.Events.AlertScheduler        polls (GenServer)
  └─ Taskmaster.Events.Alerts.fire_due/1
       ├─ marks each due event: last_alerted_on = today
       └─ Phoenix.PubSub broadcast {:alert, payload} on the "alerts" topic
            └─ TaskmasterWeb.AppLive.handle_info({:alert, payload}, ...)
                 ├─ shows the text in the status bar
                 └─ push_event("alert", payload)
                      └─ assets/js/hooks/voice_recognition.js  announce/1
                           ├─ assets/js/chime.js  playChime()
                           └─ SpeechSynthesisUtterance(payload.text)
```

### `Taskmaster.Events.Alerts`

The whole server-side rule set, and the part worth unit testing.

* `due_on/1` — alerting events that occur on a date and have not already
  announced that day. Whether an event "occurs" on a date is answered by
  `Taskmaster.Events.Recurrence`, so recurrence rules are honoured for free.
* `fire_due/1` — marks and broadcasts each of them; returns the payloads. It
  marks *before* it broadcasts, so a subscriber crashing cannot cause the same
  alert to fire again on the next poll.
* `announcement/1` / `payload/1` — the spoken sentence and the map handed to the
  client.

`payload/1` reads the assignee's name, so events must be **preloaded with
`:person`** before being passed in. `due_on/1` does this. An event with an
unloaded association is treated as unassigned rather than raising.

### `Taskmaster.Events.AlertScheduler`

A thin GenServer around `Alerts.fire_due/1`. Two things wake it:

* **A 30 second tick.** This is what catches the rollover into a new day on a
  board that is left running.
* **The `:events_changed` broadcast.** Saving an event that is due *today* would
  otherwise wait up to a tick to announce; this makes it immediate, which is
  also what makes the feature easy to try out.

The first poll is deliberately one tick after boot, not immediate: announcing
before the desktop window has connected its LiveView would mark the alert as
fired with nobody listening.

A failed poll is logged and swallowed rather than crashing the scheduler — the
next tick tries again.

Started by `Taskmaster.Application` *after* `Repo.Migrator.run/0`, because it
queries columns that migration 4 adds.

### `assets/js/chime.js`

The chime is synthesised with the Web Audio API rather than shipped as an audio
file, so there is no binary asset in the Pi image and the tone can be tuned by
editing `TONES`, `PEAK_GAIN` and `ATTACK_SECONDS` at the top of the file.

Browsers refuse to start audio before the page has seen a user gesture.
`unlockAudioOnGesture()` resumes the audio context on the first
pointerdown/touchstart/keydown — on a touchscreen the first tap does it. It
keeps listening rather than unbinding, because a context can be suspended again
when the screen blanks.

`playChime()` resolves once the chime has finished sounding, so `announce()` can
`await` it and start speaking into the silence afterwards.

### `assets/js/hooks/voice_recognition.js`

The hook already owned text-to-speech (`speak`), so it owns alerts too.

Two things to know if you are editing it:

1. **Audio output is wired up before speech recognition, and unconditionally.**
   The hook returns early when the webview has no `SpeechRecognition`; alerts
   must still chime and speak there, so that setup happens first.
2. **The microphone is muted while the app is making noise.** Reading a task
   title aloud next to an always-on microphone otherwise feeds straight back in
   as a voice command ("clean cat tree" → unrecognised → "I missed that" → …).
   `mute()`/`unmute()` gate `onresult`, with a `MIC_MUTE_TAIL_MS` tail because
   speech results lag the audio, and a `MAX_MUTE_MS` failsafe because some
   speech engines never fire `onend`.

### The Test button

`phx-click={JS.dispatch("taskmaster:test-alert", to: "#app-root")}` — a
client-side event with no server round trip. The hook listens on its own
element, reads the title straight out of `#add-event-form`, and announces
`"Alert test. <title>"`. It is there so somebody standing in front of the board
can confirm the speakers work and the volume carries.

Note that it plays a *preview*: the real announcement is built server-side by
`announcement/1` and includes the assignee's name.

---

## Timing: what is and is not guaranteed

Events carry a **date, not a time** — the whole app is date-based. So:

* An alert fires on the day it is due, at the first poll where the app is
  running and the day has arrived. On a board left on overnight that is within
  30 seconds of midnight. On a board switched on in the morning it is ~30
  seconds after boot.
* **Missed days are not replayed.** If the app is off all of Tuesday, Tuesday's
  alert never announces; Wednesday's still will. Announcing yesterday's chore
  today is more confusing than silence.
* **An alert announced with no client connected is lost.** `fire_due/1` marks
  first, so if the desktop window is closed the broadcast reaches nobody and the
  event is still marked as alerted for that day. The one-tick startup delay is
  what keeps this from happening in the normal boot sequence.

If you need a specific time of day, see the extension notes below.

---

## Configuration

| Key | Default | Purpose |
| --- | --- | --- |
| `config :taskmaster, :alert_scheduler` | `true` | Start the polling GenServer at boot. `false` in `:test`. |
| `config :taskmaster, :desktop_window` | `true` | Start the wx desktop window at boot. `false` in `:test`. |

`AlertScheduler.start_link/1` also takes `:name`, `:tick_interval` and
`:watch_events` (subscribe to `:events_changed`), which is how the tests drive
it deterministically.

---

## Testing

```
mix test
```

* `test/taskmaster/events/alerts_test.exs` — due-detection, once-per-day
  marking, recurrence, and the wording of every announcement variant.
* `test/taskmaster/events/alert_scheduler_test.exs` — `check_now/1`, the
  save-triggered poll, the tick, and the deliberate startup delay.
* `test/taskmaster_web/live/alert_form_test.exs` — the checkbox round-trips
  through the form, the alert reaches the client as a `push_event`, and the bell
  shows on the calendar.

The scheduler is disabled in `:test` (`config :taskmaster, alert_scheduler:
false`) so background polling cannot interfere; tests that want one start their
own with a controlled tick interval.

### Trying it by hand

Run the app (`iex -S mix`); the desktop window opens on a random port, and
`TaskmasterWeb.Endpoint.url()` in the IEx session prints the URL if you would
rather use a browser. Then:

1. Tap **today** on the calendar.
2. Type a title, tick **🔔 Chime & read aloud when due**, press **Test** to
   confirm you can hear it, then **Add**.

Because the scheduler polls on `:events_changed`, the alert fires within a
second of saving. Ticking the box on a *future* date and waiting is the slow
path; to test that without waiting, either back-date `start_date`, or in IEx:

```elixir
Taskmaster.Events.AlertScheduler.check_now()
```

To re-fire an alert that has already announced today, clear its mark:

```elixir
import Ecto.Query
Taskmaster.Repo.update_all(from(e in Taskmaster.Events.Event), set: [last_alerted_on: nil])
Taskmaster.Events.AlertScheduler.check_now()
```

### When nothing comes out

The chime and the speech are **two independent systems**, so which half you get
tells you where the problem is.

| Symptom | Cause |
| --- | --- |
| No chime, no speech | The alert never fired. Check the box is actually ticked (look for the 🔔 on the calendar), and that `last_alerted_on` is not already today. |
| No chime, speech works | Web Audio is suspended — the page has had no tap since it loaded. `unlockAudioOnGesture()` handles this on a real touchscreen. |
| **Chime, but no speech** | No text-to-speech voices. This is the common one. |

`speechSynthesis.speak()` is a **silent no-op when the platform has no voices**,
which on a wall-mounted board is indistinguishable from the alert never firing.
So `speak()` checks `getVoices()` first and reports upward: the hook pushes
`speech_unavailable` to `AppLive`, which shows "Can't read alerts aloud: …" in
the status bar until the page reloads. If you see the chime and that warning,
the app is working and the platform is not.

On Linux, Chrome takes its voices from **speech-dispatcher**, which is not
installed by default on many distros. On openSUSE:

```
sudo zypper install speech-dispatcher speech-dispatcher-module-espeak espeak-ng
```

Voices also load *asynchronously* in Chrome — `getVoices()` can be empty for a
moment after page load, and speaking during that window is dropped. `voices/1`
waits for `voiceschanged`, with `VOICE_LOAD_TIMEOUT_MS` as the give-up point.

---

## Extending

**A time of day.** Add an `alert_time :time` column, keep `last_alerted_on` as
is, and add `where: ^Time.utc_now() >= e.alert_time` to `Alerts.due_on/1`. Drop
the tick interval to match the precision you want. Everything downstream is
unchanged.

**Voice control.** `Taskmaster.Voice.Parser` does not understand alerts yet;
"add task feed the cat every day with an alert" would mean returning
`alert: true` in the parsed details and passing it through
`AppLive.handle_add_task/2` the same way the form does.

**Android / other platforms.** Speech *synthesis* is available in Android
WebView and every mobile browser; speech *recognition* is not in WebView at all.
See the browser notes in `CLAUDE.md`.

**A different sound.** Edit `TONES` in `assets/js/chime.js`. To use a real audio
file instead, replace `playChime()` with an `<audio>` element or a decoded
`AudioBuffer` — keep it returning a promise that resolves when the sound ends,
because `announce()` awaits it before speaking.

**Repeat / snooze.** `Alerts.fire_due/1` is the only place that decides an alert
is finished. A snooze would mean not marking `last_alerted_on` and instead
tracking a "next attempt" timestamp.

**Per-event editing.** There is no edit form yet — an event's alert flag can
only be set when it is created. Adding one means an `Events.update_event/2` and
a modal that pre-fills from the existing record; the changeset already casts
`:alert`.
