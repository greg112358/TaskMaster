# Deployment: always-on web app

The board runs as a **web app**: an Elixir server on an always-on machine, and a
wall-mounted Android tablet showing it full screen in a browser. The tablet is
just a display — it holds no state and runs no Elixir.

Two requirements shape everything here: **the app must always be running**, and
**the screen must never sleep**. Each is solved in layers, because no single
layer is reliable on its own.

---

## Run modes

| | Desktop app (default) | Web app (`TASKMASTER_WEB=1`) |
| --- | --- | --- |
| Display | Elixir Desktop wx window on the same machine | any browser on the LAN |
| Binds | `127.0.0.1`, random port | `0.0.0.0`, `$PORT` (default 4000) |
| wx window | started | not started |

Web mode is switched on entirely in `config/runtime.exs` — no code differences.
It reuses the `desktop_window: false` flag that the test environment already
uses to keep wx out of the way.

| Variable | Default | Purpose |
| --- | --- | --- |
| `TASKMASTER_WEB` | unset | `1` to serve to browsers instead of opening a window |
| `PORT` | `4000` | HTTP port |
| `TASKMASTER_HOST` | `localhost` | hostname used in generated URLs |
| `TASKMASTER_DB` | `~/.config/taskmaster/taskmaster.db` | SQLite file |
| `SECRET_KEY_BASE` | random each boot | set it, or sessions drop on restart |

`check_origin` is **off** in web mode, because the tablet connects by LAN
address which will never match the configured host. That is fine for a
household appliance on a trusted network and should not be copied to anything
reachable from the internet.

---

## Layer 1: the server always runs

Build a release — it is self-contained, boots in about a second, and needs
neither Mix nor a compiler at run time:

```bash
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release --overwrite
```

Then install the unit, which carries `Restart=always` so it returns from both a
crash and a reboot:

```bash
sudo cp deploy/taskmaster.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now taskmaster
systemctl status taskmaster
journalctl -u taskmaster -f
```

Edit `User=` and the paths in the unit if the checkout is not at
`/home/gregory/code/taskmaster`. **Re-run both build commands and
`systemctl restart taskmaster` after any code change** — the release is a
snapshot, not a live checkout.

To run it by hand while testing, without installing anything:

```bash
TASKMASTER_WEB=1 PORT=4000 mix run --no-halt
```

## Layer 2: the browser always shows it

A running server is no use if the tablet is sitting on a home screen. The page
itself is resilient — LiveView reconnects on its own when the server restarts,
so a `systemctl restart` needs no action on the tablet — but getting the browser
open and keeping it there is the tablet's job:

- **Chrome**, added to the home screen from the board's URL so it opens without
  browser chrome. Chrome is also the only mainstream Android browser with
  speech recognition (Samsung Internet works too; Firefox has none).
- **A kiosk launcher** is what actually makes this hands-off. *Fully Kiosk
  Browser* is the usual choice: it launches on boot, restores itself if it is
  dismissed, blocks navigation away from the URL, and has its own keep-screen-on
  and daily-restart settings. It solves layer 2 and most of layer 3 at once.
- Set the tablet's launcher to start it automatically, and disable the lock
  screen so a reboot lands straight on the board.

## Layer 3: the screen never sleeps

Three independent mechanisms; use at least the first two.

**1. Android developer options — "Stay awake".** Settings → About → tap Build
number 7×, then Developer options → *Stay awake while charging*. A wall-mounted
board is permanently on power, so this holds the screen on regardless of what
the browser is doing. This is the dependable one: it survives the browser being
killed. Also set Display → Screen timeout to its maximum.

**2. The in-app wake lock.** `assets/js/hooks/wake_lock.js` takes a
[Screen Wake Lock](https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API)
and re-takes it on every `visibilitychange`, because the lock is dropped
automatically whenever the page is hidden. If a request is refused it retries on
the next touch rather than giving up for the session.

> **The wake lock needs a secure context.** Served as `http://192.168.x.x:4000`,
> `navigator.wakeLock` is **undefined** and this layer simply does not exist.
> The board says so on screen rather than failing silently — see below. To get
> it working you need one of:
>
> - **HTTPS**, e.g. a certificate from a local CA or a Tailscale hostname; or
> - Chrome's `chrome://flags/#unsafely-treat-insecure-origin-as-secure`, adding
>   `http://192.168.x.x:4000` to the origin list and relaunching Chrome. This is
>   the low-effort route for a LAN appliance.
>
> If neither is in place, layer 1 above still keeps the screen on by itself.

**3. Kiosk launcher screen control.** Fully Kiosk and equivalents keep the
screen on natively, without needing a secure context.

---

## When something is missing, the board says so

Browser capabilities that are absent tend to fail *silently* —
`speechSynthesis.speak()` with no voices installed does nothing at all, and
`navigator.wakeLock` is simply not there. On a wall-mounted board with no
keyboard, that is indistinguishable from a bug in the app.

So both hooks push a `device_warning` event to `AppLive`, which shows it in the
status bar with a ⚠ until the capability comes good:

- `⚠ can't read alerts aloud: no text-to-speech voices are installed`
- `⚠ screen wake lock needs https, or a localhost address`

`AppLive.handle_event("device_warning", ...)` keys them in a map, so a hook can
clear its own warning by sending a `null` message. Add new capability checks
through the same channel rather than adding another assign.

---

## Known noise

On the **very first boot against a new database**, a few
`Exqlite.Connection ... database is locked` errors appear in the log. The pool
opens its connections while the embedded migrations are still creating tables,
and switching the journal to WAL needs an exclusive lock. The connections retry
and succeed, WAL is persisted into the database file, and **every subsequent
boot is clean**. It is noise, not a failure — but if you see it on every boot,
the database file is being recreated each time, which means `TASKMASTER_DB` is
pointing somewhere non-persistent.
