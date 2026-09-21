// Reorder the sketch board by dragging rows and tier bars.
//
// One hook on the <ol>, with rows found by delegation, so a LiveView patch that
// rewrites four hundred rows needs no rebinding.
//
// Three things make this usable on a phone as well as a desktop:
//
//   1. **Dragging starts on a handle**, never on the row body. The list is the
//      page's scrolling surface, and a vertical drag is exactly the gesture the
//      browser wants for scrolling — so the two cannot be told apart by
//      direction the way `grocery_drag.js` tells a horizontal swipe from a pan.
//      The handles carry `touch-action: none`, which is what stops the browser
//      claiming the gesture; everywhere else scrolls normally.
//
//   2. **Geometry is measured once per drag.** Hit-testing four hundred rows
//      with getBoundingClientRect on every pointermove would read layout sixty
//      times a second. Row edges are cached in document coordinates at drag
//      start and searched by bisection, so a move costs no layout at all.
//
//   3. **Edge auto-scroll.** The unranked pile is hundreds of rows below the S
//      bar, so a drag that cannot scroll cannot reach it. Holding near the top
//      or bottom of the viewport scrolls, and the drop indicator keeps tracking
//      while it does.
//
//   4. **A tier rail for long jumps.** Holding a sketch shows the tier letters
//      down the right edge. Dropping on one sends "move to the bottom of that
//      tier", so a sketch crosses four hundred rows in one gesture instead of a
//      scroll-and-drag. The rail is server-rendered, static and `phx-update=
//      "ignore"`; this hook only shows it, hides it and reads which letter the
//      finger is over. Tier bars do not get it — they only ever move a little,
//      and they already clamp against each other server-side.
//
// A drop between rows is sent as "put this row after that one", not an index.
// A filtered list is missing rows, but a neighbour still means the same thing —
// and the server resolves it against the full order. See `Taskmaster.Wkuk.move/3`.

const START_THRESHOLD_PX = 4;
const EDGE_PX = 110;
const MAX_SCROLL_PX_PER_FRAME = 18;

const WkukDrag = {
  mounted() {
    this.clearState();

    this._onDown = (event) => {
      if (this._pointerId !== null) return;
      if (event.button !== undefined && event.button !== 0) return;

      const handle = event.target.closest("[data-drag-handle]");
      if (!handle || !this.el.contains(handle)) return;

      const row = handle.closest("[data-drag-id]");
      if (!row) return;

      this._row = row;
      this._pointerId = event.pointerId;
      this._origin = { x: event.clientX, y: event.clientY };
      this._pointer = { x: event.clientX, y: event.clientY };

      // Without this a touch-drag off the handle stops sending moves.
      try {
        this.el.setPointerCapture(event.pointerId);
      } catch (_e) {}
    };

    this._onMove = (event) => {
      if (event.pointerId !== this._pointerId) return;

      this._pointer = { x: event.clientX, y: event.clientY };

      if (!this._dragging) {
        if (Math.abs(event.clientY - this._origin.y) <= START_THRESHOLD_PX) return;
        this.start();
      }

      // Suppresses the text selection a mouse drag would paint down the list.
      event.preventDefault();
    };

    this._onUp = (event) => {
      if (event.pointerId !== this._pointerId) return;

      if (this._dragging) {
        const tier = this.railTierAt(event.clientX, event.clientY);

        if (tier) {
          this.pushEvent("move_to_tier", { id: this._row.dataset.dragId, tier: tier });
        } else {
          const drop = this.dropTarget();
          // An accidental nudge lands where it started. Pushing that would make
          // the server renumber and re-render the whole list for nothing.
          if (drop && drop.after !== this._originalAfter) {
            this.pushEvent("move", { id: this._row.dataset.dragId, after: drop.after });
          }
        }
      }

      this.reset();
    };

    this._onCancel = (event) => {
      if (event.pointerId !== this._pointerId) return;
      this.reset();
    };

    this.el.addEventListener("pointerdown", this._onDown);
    this.el.addEventListener("pointermove", this._onMove);
    this.el.addEventListener("pointerup", this._onUp);
    this.el.addEventListener("pointercancel", this._onCancel);
  },

  // A patch landed — the other tablet reordered, or a filter changed the rows.
  // The cached edges describe a list that no longer exists.
  updated() {
    if (this._dragging) this.measure();
  },

  destroyed() {
    this.reset();
    this.el.removeEventListener("pointerdown", this._onDown);
    this.el.removeEventListener("pointermove", this._onMove);
    this.el.removeEventListener("pointerup", this._onUp);
    this.el.removeEventListener("pointercancel", this._onCancel);
  },

  start() {
    this._dragging = true;

    this._ghost = this.buildGhost(this._row);
    document.body.appendChild(this._ghost);
    this._row.classList.add("opacity-30");

    this._indicator = document.createElement("div");
    this._indicator.className = "fixed left-0 right-0 z-50 h-1 bg-primary pointer-events-none";
    document.body.appendChild(this._indicator);

    document.body.classList.add("cursor-grabbing");

    this.measure();

    // Sketches only; a tier bar's drag is short and clamped by the server.
    this._rail = this._row.dataset.dragId.startsWith("s-")
      ? document.getElementById("wkuk-rail")
      : null;
    if (this._rail) this._rail.style.display = "flex";

    this._frame = requestAnimationFrame(() => this.tick());
  },

  buildGhost(row) {
    const rect = row.getBoundingClientRect();
    const ghost = row.cloneNode(true);

    // A clone carries the original's ids and hook, and two elements sharing one
    // id is a bad thing to hand LiveView.
    ghost.removeAttribute("id");
    ghost.removeAttribute("phx-hook");
    ghost.querySelectorAll("[id]").forEach((el) => el.removeAttribute("id"));

    ghost.style.position = "fixed";
    ghost.style.left = `${rect.left}px`;
    ghost.style.top = "0";
    ghost.style.width = `${rect.width}px`;
    ghost.style.margin = "0";
    ghost.style.pointerEvents = "none";
    ghost.style.zIndex = "60";
    ghost.style.opacity = "0.95";
    ghost.style.boxShadow = "0 10px 30px rgba(0,0,0,0.35)";

    this._grabOffset = this._origin.y - rect.top;
    ghost.style.transform = `translateY(${rect.top}px)`;
    return ghost;
  },

  // Row edges in *document* coordinates, so scrolling does not invalidate them.
  // Rows are in DOM order, which is list order, so the array is already sorted
  // by `mid` and can be bisected.
  measure() {
    const scrollY = window.scrollY;
    const draggedId = this._row && this._row.dataset.dragId;

    this._targets = Array.from(this.el.querySelectorAll("[data-drag-id]"))
      .filter((el) => el.dataset.dragId !== draggedId && el.offsetParent !== null)
      .map((el) => {
        const rect = el.getBoundingClientRect();
        return {
          id: el.dataset.dragId,
          top: rect.top + scrollY,
          bottom: rect.bottom + scrollY,
          mid: rect.top + scrollY + rect.height / 2,
        };
      });

    this._originalAfter = this.neighbourAbove(draggedId);
  },

  // The id the dragged row currently sits below, which is what the server would
  // be told if it were dropped without moving.
  neighbourAbove(draggedId) {
    const rows = Array.from(this.el.querySelectorAll("[data-drag-id]")).filter(
      (el) => el.offsetParent !== null
    );
    const index = rows.findIndex((el) => el.dataset.dragId === draggedId);
    return index > 0 ? rows[index - 1].dataset.dragId : null;
  },

  dropTarget() {
    if (!this._targets) return null;

    const docY = this._pointer.y + window.scrollY - this._grabOffset + this.rowHalfHeight();
    const rows = this._targets;

    let lo = 0;
    let hi = rows.length;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (rows[mid].mid < docY) lo = mid + 1;
      else hi = mid;
    }

    return {
      index: lo,
      after: lo === 0 ? null : rows[lo - 1].id,
      edge: lo < rows.length ? rows[lo].top : rows.length ? rows[rows.length - 1].bottom : 0,
    };
  },

  rowHalfHeight() {
    return this._row ? this._row.offsetHeight / 2 : 0;
  },

  tick() {
    if (!this._dragging) return;

    const tier = this.railTierAt(this._pointer.x, this._pointer.y);
    this.highlightRail(tier);

    // Over the rail the drop is a tier, not a place between rows: no insertion
    // line, and no edge scroll, which would run the list away under the finger.
    if (!tier) this.autoScroll();

    const top = this._pointer.y - this._grabOffset;
    this._ghost.style.transform = `translateY(${top}px)`;

    const drop = tier ? null : this.dropTarget();
    this._indicator.style.display = drop ? "block" : "none";
    if (drop) this._indicator.style.top = `${drop.edge - window.scrollY}px`;

    this._frame = requestAnimationFrame(() => this.tick());
  },

  // The tier letter under the finger, or null. `elementFromPoint` rather than a
  // cached rect: the rail is fixed and eight elements tall, so there is nothing
  // worth caching, and the ghost has `pointer-events: none` so it never answers.
  railTierAt(x, y) {
    if (!this._rail) return null;
    const el = document.elementFromPoint(x, y);
    const target = el && el.closest("[data-rail-tier]");
    return target ? target.dataset.railTier : null;
  },

  highlightRail(tier) {
    if (tier === this._railHot) return;

    this.clearRailHighlight();
    if (!tier || !this._rail) return;

    const el = this._rail.querySelector(`[data-rail-tier="${tier}"]`);
    if (el) {
      el.classList.add("ring-4", "ring-white", "scale-105");
      this._railHot = tier;
    }
  },

  clearRailHighlight() {
    if (this._railHot && this._rail) {
      const el = this._rail.querySelector(`[data-rail-tier="${this._railHot}"]`);
      if (el) el.classList.remove("ring-4", "ring-white", "scale-105");
    }
    this._railHot = null;
  },

  autoScroll() {
    const y = this._pointer.y;
    const height = window.innerHeight;
    let delta = 0;

    if (y < EDGE_PX) {
      delta = -MAX_SCROLL_PX_PER_FRAME * ((EDGE_PX - y) / EDGE_PX);
    } else if (y > height - EDGE_PX) {
      delta = MAX_SCROLL_PX_PER_FRAME * ((y - (height - EDGE_PX)) / EDGE_PX);
    }

    if (delta !== 0) window.scrollBy(0, delta);
  },

  reset() {
    if (this._frame) cancelAnimationFrame(this._frame);
    if (this._ghost) this._ghost.remove();
    if (this._indicator) this._indicator.remove();
    // Detached if a patch replaced the row mid-drag; harmless either way.
    if (this._row) this._row.classList.remove("opacity-30");
    document.body.classList.remove("cursor-grabbing");

    this.clearRailHighlight();
    if (this._rail) this._rail.style.display = "none";

    if (this._pointerId !== null) {
      try {
        this.el.releasePointerCapture(this._pointerId);
      } catch (_e) {}
    }

    this.clearState();
  },

  clearState() {
    this._dragging = false;
    this._pointerId = null;
    this._row = null;
    this._ghost = null;
    this._indicator = null;
    this._rail = null;
    this._railHot = null;
    this._targets = null;
    this._originalAfter = null;
    this._origin = null;
    this._pointer = { x: 0, y: 0 };
    this._grabOffset = 0;
    this._frame = null;
  },
};

export default WkukDrag;
