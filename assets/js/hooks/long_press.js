// Press and hold a grocery item to forget the word behind it.
//
// A touchscreen has no right-click, so hold is the only "secondary action"
// available. The fiddly part is that a hold also produces a normal tap when the
// finger lifts — which would toggle the item as well as opening the dialog — so
// the click that follows a fired hold is swallowed in the capture phase, before
// LiveView's delegated handler on document ever sees it.

const HOLD_MS = 600;

// A finger drifting a few pixels is still a hold; a drag is not.
const MOVE_TOLERANCE_PX = 10;

const LongPress = {
  mounted() {
    this._fired = false;

    this._onDown = (event) => {
      this._fired = false;
      this._origin = { x: event.clientX, y: event.clientY };

      clearTimeout(this._timer);
      this._timer = setTimeout(() => {
        this._fired = true;
        this.el.classList.add("ring-4", "ring-warning");
        this.pushEvent("hold_grocery_item", { name: this.el.dataset.name });
      }, HOLD_MS);
    };

    this._onMove = (event) => {
      if (!this._origin) return;
      const dx = Math.abs(event.clientX - this._origin.x);
      const dy = Math.abs(event.clientY - this._origin.y);
      if (dx > MOVE_TOLERANCE_PX || dy > MOVE_TOLERANCE_PX) this.cancel();
    };

    this._onUp = () => this.cancel();

    // A hold on Android otherwise raises the text-selection menu over the top
    // of our dialog.
    this._onContextMenu = (event) => event.preventDefault();

    this._onClick = (event) => {
      if (!this._fired) return;
      this._fired = false;
      event.preventDefault();
      event.stopPropagation();
    };

    this.el.addEventListener("pointerdown", this._onDown);
    this.el.addEventListener("pointermove", this._onMove);
    this.el.addEventListener("pointerup", this._onUp);
    this.el.addEventListener("pointercancel", this._onUp);
    this.el.addEventListener("pointerleave", this._onUp);
    this.el.addEventListener("contextmenu", this._onContextMenu);
    this.el.addEventListener("click", this._onClick, true);
  },

  cancel() {
    clearTimeout(this._timer);
    this._origin = null;
    this.el.classList.remove("ring-4", "ring-warning");
  },

  destroyed() {
    clearTimeout(this._timer);
    this.el.removeEventListener("pointerdown", this._onDown);
    this.el.removeEventListener("pointermove", this._onMove);
    this.el.removeEventListener("pointerup", this._onUp);
    this.el.removeEventListener("pointercancel", this._onUp);
    this.el.removeEventListener("pointerleave", this._onUp);
    this.el.removeEventListener("contextmenu", this._onContextMenu);
    this.el.removeEventListener("click", this._onClick, true);
  },
};

export default LongPress;
