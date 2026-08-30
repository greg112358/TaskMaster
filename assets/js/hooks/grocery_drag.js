// Drag a grocery row onto another column to move it to that list.
//
// One hook on the grid rather than one per row: a row already carries
// phx-hook="LongPress", and an element carries only one hook. Rows are found by
// delegation from the container, so a LiveView patch that adds or removes rows
// needs no rebinding.
//
// The gesture is deliberately horizontal. Rows are also the scrolling surface on
// a phone, so each row sets `touch-action: pan-y`: the browser keeps vertical
// pans (and sends us `pointercancel` when it takes one), we keep horizontal
// ones. A drag therefore starts only once the finger has travelled further
// across than down. Holding still instead is the long press, which any movement
// past its own tolerance cancels — the two gestures cannot both fire.

const DRAG_THRESHOLD_PX = 12;

const GroceryDrag = {
  mounted() {
    this._dragged = false;
    this.reset();

    this._onDown = (event) => {
      // The click swallowed below is consumed by the next press if the release
      // happened outside this container and our click listener never ran.
      this._dragged = false;

      if (event.button !== undefined && event.button !== 0) return;

      const row = event.target.closest("[data-item-id]");
      if (!row) return;

      this._row = row;
      this._pointerId = event.pointerId;
      this._origin = { x: event.clientX, y: event.clientY };
    };

    this._onMove = (event) => {
      if (!this._row || event.pointerId !== this._pointerId) return;

      const dx = event.clientX - this._origin.x;
      const dy = event.clientY - this._origin.y;

      if (!this._dragging) {
        // Further down than across: the browser is about to scroll, and this
        // gesture is never becoming a drag.
        if (Math.abs(dy) > DRAG_THRESHOLD_PX && Math.abs(dy) >= Math.abs(dx)) {
          return this.reset();
        }
        if (Math.abs(dx) <= DRAG_THRESHOLD_PX) return;
        if (!this.start()) return;
      }

      // Stops the text selection a mouse drag would otherwise paint over the
      // list, and suppresses the synthesised click on touch.
      event.preventDefault();
      this.moveGhost(event.clientX, event.clientY);
      this.highlight(this.columnAt(event.clientX, event.clientY));
    };

    this._onUp = (event) => {
      if (!this._dragging) return this.reset();

      const column = this.columnAt(event.clientX, event.clientY);
      const category = column && column.dataset.category;

      if (category && category !== this._sourceColumn.dataset.category) {
        this.pushEvent("recategorize_grocery", {
          id: this._row.dataset.itemId,
          category: category,
        });
      }

      // The release still produces a click, which would tick the row off.
      this._dragged = true;
      this.reset();
    };

    this._onCancel = () => this.reset();

    this._onClick = (event) => {
      if (!this._dragged) return;
      this._dragged = false;
      event.preventDefault();
      event.stopPropagation();
    };

    this.el.addEventListener("pointerdown", this._onDown);
    this.el.addEventListener("pointermove", this._onMove);
    this.el.addEventListener("pointerup", this._onUp);
    this.el.addEventListener("pointercancel", this._onCancel);
    // Capture phase, so it runs before LiveView's delegated handler on document.
    this.el.addEventListener("click", this._onClick, true);
  },

  // False when the drag is refused, so the caller stops rather than dragging a
  // ghost with no source column behind it.
  start() {
    // A modal is up: the finger belongs to it, not to the list underneath.
    if (document.querySelector("#forget-dialog, #categorize-dialog")) {
      this.reset();
      return false;
    }

    this._sourceColumn = this._row.closest("[data-category]");
    if (!this._sourceColumn) {
      this.reset();
      return false;
    }

    this._dragging = true;
    this._ghost = this.buildGhost(this._row);
    document.body.appendChild(this._ghost);
    this._row.classList.add("opacity-30");

    // Keeps the moves coming once the finger leaves the grid.
    try {
      this.el.setPointerCapture(this._pointerId);
    } catch (_e) {}

    return true;
  },

  buildGhost(row) {
    const rect = row.getBoundingClientRect();
    const ghost = row.cloneNode(true);

    // A clone carries the original's ids and hook, and two elements sharing one
    // id is a bad thing to hand LiveView.
    ghost.removeAttribute("id");
    ghost.removeAttribute("phx-hook");
    ghost.querySelectorAll("[id]").forEach((el) => el.removeAttribute("id"));

    ghost.classList.add("bg-base-100", "shadow-xl", "px-1");
    ghost.style.position = "fixed";
    ghost.style.left = "0";
    ghost.style.top = "0";
    ghost.style.width = `${rect.width}px`;
    // So elementFromPoint answers with the column under the finger, not this.
    ghost.style.pointerEvents = "none";
    ghost.style.zIndex = "60";
    ghost.style.opacity = "0.9";

    this._grab = { x: this._origin.x - rect.left, y: this._origin.y - rect.top };
    return ghost;
  },

  moveGhost(x, y) {
    const dx = x - this._grab.x;
    const dy = y - this._grab.y;
    this._ghost.style.transform = `translate(${dx}px, ${dy}px)`;
  },

  columnAt(x, y) {
    const el = document.elementFromPoint(x, y);
    return el && el.closest("[data-category]");
  },

  highlight(column) {
    if (column === this._highlighted) return;

    this.clearHighlight();

    if (column && column !== this._sourceColumn) {
      column.classList.add("ring-2", "ring-primary", "bg-primary/10");
      this._highlighted = column;
    }
  },

  clearHighlight() {
    if (!this._highlighted) return;
    this._highlighted.classList.remove("ring-2", "ring-primary", "bg-primary/10");
    this._highlighted = null;
  },

  reset() {
    if (this._ghost) this._ghost.remove();
    // Detached if another tablet deleted the row mid-drag; harmless either way.
    if (this._row) this._row.classList.remove("opacity-30");
    this.clearHighlight();

    if (this._dragging) {
      try {
        this.el.releasePointerCapture(this._pointerId);
      } catch (_e) {}
    }

    this._dragging = false;
    this._row = null;
    this._ghost = null;
    this._sourceColumn = null;
    this._origin = null;
    this._pointerId = null;
  },

  destroyed() {
    this.reset();
    this.el.removeEventListener("pointerdown", this._onDown);
    this.el.removeEventListener("pointermove", this._onMove);
    this.el.removeEventListener("pointerup", this._onUp);
    this.el.removeEventListener("pointercancel", this._onCancel);
    this.el.removeEventListener("click", this._onClick, true);
  },
};

export default GroceryDrag;
