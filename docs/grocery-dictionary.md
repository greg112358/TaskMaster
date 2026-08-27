# The grocery dictionary

The board decides which of the three lists an item goes on by looking the word
up in a dictionary the family owns and edits. Nothing about that vocabulary is
baked into the code at run time: every word, including the several hundred it
ships with, can be taught, moved or forgotten from the Groceries screen.

## What it does on screen

| Action | What happens |
| --- | --- |
| Type | Matching words appear beneath the box, prefix matches first |
| Tap a suggestion | Adds it straight to that word's list |
| Add a word it knows | Files it silently |
| **Add a word it doesn't know** | Asks *"Which list?"* — the answer files the item **and** teaches the word, so it is asked only once |
| Tap the red × on a suggestion | Asks to confirm, then forgets the word |
| **Press and hold an item** | Asks to confirm, then forgets the word behind it |

Forgetting only affects the dictionary. Anything already on the shopping list
stays exactly where it is — the word simply stops being suggested, and the board
asks about it again next time.

## Where the words come from

`Taskmaster.Grocery.DefaultTerms` holds the built-in vocabulary, and migration 5
copies it into the `grocery_terms` table. From then on the table is the only
source of truth — **editing `DefaultTerms` has no effect on an existing
database.**

That is deliberate. The alternative, keeping the built-ins in code and layering
user words on top, produces a two-tier dictionary where holding "milk" appears
to do nothing because "milk" is not the kind of word you are allowed to delete.
One uniform, editable list has no such corner.

## How a word is matched

`Dictionary.category_for/1` answers in two steps:

1. an **exact** match on the normalised name; failing that
2. the **longest** known term appearing in the name, **on word boundaries**.

Step 2 is what puts "whole milk" on the red list without anyone teaching it.
*Longest* rather than first is what keeps "corned beef" out of produce when
"corn" is also known — the old `cond`-based categoriser resolved that only by
accident of list order.

### Whole words, and why plurals are the acceptable loss

A plain substring test makes "ham" match **graham** crackers and "sole" match
**casserole** — silently, with nothing on the board to explain why the colour is
wrong. Matching pads both sides with a space so a term has to line up with whole
words.

The cost is plurals: "tomatoes" no longer resolves via "tomato". That is the
right trade now that unknown words are handled well — an unrecognised word asks
which list it goes on, is answered once, and is never asked about again. A wrong
guess just looks broken.

> **A bug worth remembering.** The built-in lists used `~w(...)` with escaped
> spaces for multi-word terms, and `~w` splits on an escaped space exactly as it
> does on a real one — `~w(hot\ dog)` is `["hot", "dog"]`. All 48 multi-word
> terms were being shredded, and the fragments then matched far too much: "hot"
> put *hot sauce* on the red list. `DefaultTerms` is now an explicit list of
> strings. If you add terms there, do not reach for `~w`.

Names are normalised on the way in and on the way out: lowercased, trimmed, with
runs of whitespace collapsed. `Dictionary.normalize/1` is the only thing that
should be producing a stored name.

Anything neither step matches is `:unknown`, which is the signal for the UI to
ask. Where there is nobody to ask — the voice command, which cannot put up a
dialog — `category_for!/1` falls back to "everything else" and does **not**
teach the word, so typing it later still prompts properly.

### Holding an item forgets the word, not the item

Holding "whole milk" offers to forget **"milk"**, because that is the entry
actually responsible for its colour; "whole milk" was never in the dictionary.
`Dictionary.matching_term/1` is what resolves this, and where nothing matches at
all the dialog says so plainly rather than offering a delete that would do
nothing.

## Structure

| Module | Role |
| --- | --- |
| `Taskmaster.Grocery.Dictionary` | lookup, suggestions, learn/forget, PubSub |
| `Taskmaster.Grocery.Term` | the schema; normalises names in its changeset |
| `Taskmaster.Grocery.DefaultTerms` | built-in vocabulary, seed data only |
| `TaskmasterWeb.GroceryLive` | the screen, including both dialogs |
| `assets/js/hooks/long_press.js` | press-and-hold on a touchscreen |

### Why the screen keeps its own state

`GroceryLive` is, with `CalendarLive`, one of only two stateful components: the
typed query, the suggestion list and the two dialogs are view state nobody else
needs. Writes still go up to `AppLive` via `send(self(), ...)`, matching the
rest of the app.

### Ordering matters when forgetting

`handle_event("forget", ...)` must **not** recompute the suggestion list itself.
The delete is handed to `AppLive` as a message, so recomputing immediately runs
*before* the write and leaves the just-forgotten word sitting on screen — which
is exactly the bug the test "and it stops being suggested" exists to catch.

Instead `Dictionary.learn/2` and `forget/1` broadcast `:dictionary_changed`;
`AppLive` forwards that to the component, which refreshes from the database once
the write has actually landed. This is also what keeps a second tablet correct.

The round trip is component → `AppLive` → PubSub → `AppLive` → component. Four
hops, invisible in use, but a LiveView test has to let them drain — see
`settle/1` in `test/taskmaster_web/live/grocery_dictionary_test.exs`.

### Long press

A touchscreen has no right-click, so hold is the only secondary action
available. Two details in `long_press.js` are load-bearing: the click that
follows a fired hold is swallowed **in the capture phase**, before LiveView's
delegated handler on `document` sees it (otherwise a hold would also toggle the
item), and `contextmenu` is suppressed so Android's text-selection menu does not
open over the dialog. A finger drifting more than `MOVE_TOLERANCE_PX` cancels
the hold, so scrolling the list does not trigger it.

The hook cannot address a component directly, so it pushes `hold_grocery_item`
to `AppLive`, which hands it on with `send_update`.

## Extending

**A screen to browse the whole dictionary.** `Dictionary.list/0` already returns
everything alphabetically; Settings is the natural home.

**Teaching by voice.** `Taskmaster.Voice.Parser` has no grammar for it. "Add
quinoa to groceries" currently files it under everything-else without learning
it; a phrase like "quinoa is produce" would map to `Dictionary.learn/2`.

**Plurals and typos.** Matching is whole-word, so "tomatoes" does not resolve
via "tomato" — it simply asks once and is learned. If that becomes tiresome,
stemming or a trigram distance goes in `Dictionary.matching_term/1`, the single
place matching is decided.
