// Keeps "hide chores" (the calendar's chore filter) in localStorage so it
// survives a refresh. `CalendarLive.hide_chores` is otherwise per-connection
// state that resets with the socket — see `TaskmasterWeb.CalendarLive`.
//
// `this.el` is the checkbox itself: there's nothing else on it worth
// targeting, and it keeps `el.checked` a one-line read/write.

const STORAGE_KEY = "taskmaster:hideChores";

const ChoreFilter = {
  mounted() {
    this.restore();
    this.el.addEventListener("change", () => this.store());
  },

  // One-time sync on connect. The checkbox's rendered `checked` already
  // reflects the server's default (`false`), so only a stored `true` needs
  // pushing up; `restore_hide_chores` lands on `AppLive`, same as every
  // other calendar control.
  restore() {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored === null) return;

      const hide = stored === "true";
      if (hide !== this.el.checked) {
        this.pushEvent("restore_hide_chores", { hide });
      }
    } catch (error) {
      this.warn(error.name);
    }
  },

  store() {
    try {
      localStorage.setItem(STORAGE_KEY, this.el.checked);
      this.clearWarning();
    } catch (error) {
      this.warn(error.name);
    }
  },

  // `<api>: <reason>` — see `deslop` skill.
  warn(reason) {
    console.warn(`choreFilter: ${reason}`);
    this.pushEvent("device_warning", { key: "chore_filter", message: `choreFilter: ${reason}` });
  },

  clearWarning() {
    this.pushEvent("device_warning", { key: "chore_filter", message: null });
  },
};

export default ChoreFilter;
