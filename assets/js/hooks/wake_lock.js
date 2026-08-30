// Holds a screen wake lock so the wall-mounted board never blanks. A board you
// have to poke before you can read it is worse than no board.
//
// Two things make this fiddlier than it looks:
//
//   * Screen Wake Lock needs a **secure context**. Served over plain http:// to
//     a LAN address, `navigator.wakeLock` is simply undefined — see
//     docs/deployment.md for the ways around that.
//   * The lock is dropped automatically every time the page is hidden (screen
//     off, tab switched, app backgrounded), so it has to be taken again on
//     visibilitychange rather than once at mount.
//
// The wake lock is belt-and-braces regardless: the Android "stay awake while
// charging" developer option is the more dependable half, because it survives
// the browser being killed.

const WakeLock = {
  mounted() {
    this._onVisibilityChange = () => {
      if (document.visibilityState === "visible") this.acquire();
    };
    document.addEventListener("visibilitychange", this._onVisibilityChange);

    this.acquire();
  },

  async acquire() {
    if (!("wakeLock" in navigator)) {
      this.warn(window.isSecureContext ? "not supported" : "needs https");
      return;
    }

    if (this._lock && !this._lock.released) return;

    try {
      this._lock = await navigator.wakeLock.request("screen");
      this._lock.addEventListener("release", () => {
        console.log("Screen wake lock released");
      });
      this.clearWarning();
    } catch (error) {
      // Chrome refuses the request when the document is not visible, and some
      // versions want a user gesture first. A tap on the board fixes both, so
      // retry on the next one rather than giving up for the session.
      this.warn(error.name);
      this.retryOnNextTouch();
    }
  },

  retryOnNextTouch() {
    if (this._retryBound) return;
    this._retryBound = true;

    this._onTouch = () => {
      this._retryBound = false;
      window.removeEventListener("pointerdown", this._onTouch);
      this.acquire();
    };

    window.addEventListener("pointerdown", this._onTouch, { once: true, passive: true });
  },

  // `<api>: <reason>` — a wall board has no console, so the API name is the
  // actionable half. See the `deslop` skill.
  warn(reason) {
    console.warn(`wakeLock: ${reason}`);
    this.pushEvent("device_warning", { key: "wake_lock", message: `wakeLock: ${reason}` });
  },

  clearWarning() {
    this.pushEvent("device_warning", { key: "wake_lock", message: null });
  },

  destroyed() {
    document.removeEventListener("visibilitychange", this._onVisibilityChange);
    if (this._onTouch) window.removeEventListener("pointerdown", this._onTouch);
    if (this._lock && !this._lock.released) this._lock.release();
  },
};

export default WakeLock;
