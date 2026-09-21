# The WKUK sketch ranking board

A second front end on the same release, at `/wkuk`. It has nothing to do with
the wall board: different screen, different device, different sizing rules. It
shares the login and the database and nothing else.

| Path | What |
| --- | --- |
| `/wkuk` | pick a ranker |
| `/wkuk/greg`, `/wkuk/john` | that person's board |

Both are behind `TaskmasterWeb.Plugs.Auth` like every other page. The two
"users" are **not** two logins — the path segment is the whole of the identity.
Anyone through the front door can open either board. `Taskmaster.Wkuk.users/0`
is the list; a segment outside it redirects to `/wkuk`.

## The data model

Three tables, created by migration 7; migration 9 refreshes descriptions.

`wkuk_sketches` is the shared catalogue: 384 rows, one per sketch, seeded from
`Taskmaster.Wkuk.Catalog`. Same rule as `Grocery.DefaultTerms` — **editing the
catalogue module does nothing to an existing database.** A correction goes
through the screen.

`wkuk_rankings` and `wkuk_dividers` are per person.

| Column | Scope | Editable |
| --- | --- | --- |
| `sketches.title`, `season`, `episode` | shared | no |
| `sketches.description` | shared | yes |
| `sketches.youtube_url` | shared | yes |
| `rankings.position`, `dividers.position` | per person | by dragging |
| `rankings.notes` | per person | yes |

Two PubSub topics follow that split. `wkuk:shared` carries a sketch edit to
everybody; `wkuk:user:<name>` carries a reorder or a note to one board. A board
subscribes to both and reloads on either.

## One list, and tiers that are computed

A board is **one ordered sequence** holding both kinds of row. Rankings and
dividers carry a `position` in the same integer space; the sequence is the two
tables merged and sorted, and positions are dense (0..n-1).

A sketch has **no stored tier**. Its tier is whichever divider sits above it.
That is the whole reason the bars are draggable: moving one bar re-tiers
everything it crosses without touching a single sketch row.

There are eight bars — `S A B C D E F unranked` — and `unranked` is an ordinary
divider marking the floor of the ranked region. Everything below it is unranked,
which is where all 384 sketches start.

### Which bars move

Seven of the eight. **The `S` bar is pinned to index 0** and is rendered without
a handle; `move/3` refuses it.

That is not a missing feature. Eight regions have seven boundaries *between*
them, and the seven draggable bars are exactly those boundaries: drag `A` to
resize S, drag `unranked` to resize F. The `S` bar is the top label, not a
boundary — there is nothing above it to trade space with.

A bar may not cross another bar. `move/3` clamps the target index into the
window between the dragged bar's canonical neighbours, so `S A B C D E F
unranked` order holds whatever the client sends.

## The move protocol

The browser sends `{"id" => "s-12", "after" => "d-B"}`: *put this row
immediately below that one*. `after` may be `nil`, meaning the top of the list.

**A neighbour, not an index.** The list may be filtered, so the rows on screen
are not the rows in the database — but a neighbour still means the same thing
when rows are hidden, and the server resolves it against the full order. This is
also why dividers survive the filter: drop them and a search would leave nothing
to drop onto.

`move_to_tier` sends `{"id" => "s-12", "tier" => "A"}` and is sketches only; a
divider id or a tier outside `Divider.tiers/0` answers `:error`.

Ids on the wire are `s-<sketch_id>` and `d-<tier>`. They are client input, so
`decode_id/1` parses with `Integer.parse/1` and answers `:error` on anything it
does not recognise — never `String.to_atom`, never a raise (`bug-patterns` P4).

## The drag hook

`assets/js/hooks/wkuk_drag.js`, one hook on the `<ol>`, rows found by
delegation. Three things make it work on a phone as well as a desktop.

**Dragging starts on a handle.** The list is the page's scrolling surface and a
vertical drag is exactly the gesture the browser wants for scrolling, so the two
cannot be separated by direction the way `grocery_drag.js` separates a
horizontal swipe from a vertical pan. Handles carry `touch-action: none`, which
is what stops the browser claiming the gesture; everywhere else scrolls
normally. The handle is 48px wide and the full height of the row.

**Geometry is measured once per drag.** Hit-testing 392 rows with
`getBoundingClientRect` on every `pointermove` would read layout sixty times a
second. Row edges are cached in *document* coordinates at drag start and
searched by bisection, so scrolling does not invalidate them and a move costs no
layout at all. `updated()` re-measures if a patch lands mid-drag.

**Edge auto-scroll.** The unranked pile is hundreds of rows below the `S` bar,
so a drag that cannot scroll cannot reach it. Holding near the top or bottom of
the viewport scrolls, and the drop indicator keeps tracking while it does.

**A tier rail for long jumps.** Dragging a row four hundred places is a scroll
and a drag at once, and it is miserable. Holding a *sketch* shows the tier letters
in a column down the right edge, and dropping on one sends
`move_to_tier` instead of `move`. The sketch lands at the **bottom** of that
tier, just above the next bar (`Wkuk.move_to_tier/3`); `unranked` is the end of
the list. Bottom, not top, so a person filling a tier in order is not fighting
every new arrival landing above what they already placed. The board keeps its
scroll position, so the next sketch is one more gesture from where they were,
and the status line says where the last one went.

The rail is server-rendered, static and `phx-update="ignore"`; the hook only
shows it, hides it, and reads the letter under the pointer. Over it there is no
insertion line and no edge auto-scroll, which would run the list away under the
finger. Tier bars do not get the rail: they only ever move a little and already
clamp against each other.

The drop is shown as an insertion line plus a floating ghost, and the real DOM
is never reordered by hand — LiveView owns it, and a patch landing mid-drag would
fight anything the hook moved. A drop that lands where it started pushes
nothing.

## Sizing is not the wall board's sizing

CLAUDE.md's "readable from ten feet, no small text" rule is a constraint on the
appliance. This is a phone-and-desktop app holding four hundred rows, so it uses
ordinary type with touch-sized hit targets rather than `text-xl` throughout.
**Do not "fix" it to match the board.**

## YouTube links

`youtube_url` is deliberately **not** seeded. There is no authoritative mapping
from a sketch title to a video id, and a wrong link on 384 rows is worse than
none. Until somebody pastes one, the ▶ button opens a YouTube *search* for the
title and renders dimmed. `Sketch.changeset/2` refuses anything that is not an
`http`/`https` URL, which is what keeps a `javascript:` URL off the page.

## Descriptions

Each sketch has a one-line description, shared by both rankers so that one person
fixing one fixes it for both. Titles are not editable; descriptions are.

**Where the text comes from.** The per-sketch synopses in Wikipedia's *List of The
Whitest Kids U' Know episodes*, condensed to one line each. The first draft was
written from the titles alone and was wrong often enough to be useless, which is
why this is sourced. Where the source says little, so does the description:
*Peeing* is "Zach suffers embarrassment at the office" because that is all it
gives. Inventing more would be worse than saying so. Fix those on the board.
*Jerkocaust* ("Nazis look for jerks") and *iPod Shuffle* are the owner's wording.

**Revising the catalogue.** Editing `Taskmaster.Wkuk.Catalog` changes a fresh
database. For an existing one, add a migration that calls
`Wkuk.refresh_unedited_descriptions/0` (migration 9 is the worked example). It
rewrites a description only where `updated_at == inserted_at`, meaning nobody has
touched the row from the screen, so a correction someone typed survives. It is
conservative: changing a row's YouTube link also moves `updated_at`, and that
row's description is then left alone.

The catalogue is parsed at compile time from `season|episode|title|description`
lines, so a description cannot contain `|`, and the write path caps one at 200
characters.

## Adding a sketch

Append a row to `Catalog`, then let `ensure_seeded/1` do the rest — it runs at
every mount, finds sketches with no ranking row for that person, and appends
them to the bottom of the unranked pile. No migration, and nobody's existing
order moves.
