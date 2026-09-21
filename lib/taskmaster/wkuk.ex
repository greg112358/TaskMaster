defmodule Taskmaster.Wkuk do
  @moduledoc """
  The sketch ranking board behind `/wkuk`.

  ## One list, two kinds of row

  A person's board is a single ordered sequence holding both their sketches
  (`Taskmaster.Wkuk.Ranking`) and their tier bars (`Taskmaster.Wkuk.Divider`).
  Both tables carry a `position` in the *same* integer space, so the sequence is
  the two tables merged and sorted. Positions are dense — 0..n-1 — and
  `move/3` rewrites the ones that shifted.

  A sketch's tier is **not stored**. It is the tier of the nearest divider above
  it, so dragging one bar re-tiers everything it crosses without touching a
  single sketch row. `unranked` is a divider like any other and marks the floor
  of the ranked region.

  ## What is shared and what is not

  | Column | Scope |
  | --- | --- |
  | `wkuk_sketches.title`, `season`, `episode` | shared, read-only |
  | `wkuk_sketches.description`, `youtube_url` | shared, editable |
  | `wkuk_rankings.position`, `wkuk_dividers.position` | per person |
  | `wkuk_rankings.notes` | per person |

  Two PubSub topics follow that split: an edit to a sketch reaches everybody, a
  reorder reaches only the person who made it. See `subscribe/1`.

  ## Ids on the wire

  The browser identifies a row as `"s-<sketch_id>"` or `"d-<tier>"`. That is
  client input, so `decode_id/1` parses rather than converts and every entry
  point answers `:error` on anything it does not recognise.
  """

  import Ecto.Query

  alias Taskmaster.Repo
  alias Taskmaster.Wkuk.{Divider, Ranking, Sketch}

  @users ~w(greg john)
  @shared_topic "wkuk:shared"

  @doc "The people with a board. A path segment outside this list is a 404."
  def users, do: @users

  def user?(user), do: user in @users

  @doc """
  Subscribes to both halves: sketch edits, which everybody sees, and this
  person's own ordering and notes.
  """
  def subscribe(user) when user in @users do
    Phoenix.PubSub.subscribe(Taskmaster.PubSub, @shared_topic)
    Phoenix.PubSub.subscribe(Taskmaster.PubSub, user_topic(user))
  end

  defp user_topic(user), do: "wkuk:user:" <> user

  defp broadcast_shared do
    Phoenix.PubSub.broadcast(Taskmaster.PubSub, @shared_topic, :wkuk_sketches_changed)
  end

  defp broadcast_user(user) do
    Phoenix.PubSub.broadcast(Taskmaster.PubSub, user_topic(user), :wkuk_board_changed)
  end

  # ---------------------------------------------------------------- seeding --

  @doc """
  Creates whatever this person is missing: their eight tier bars on a first
  visit, and a ranking row for every sketch that has none.

  Idempotent, and the reason a sketch added to the catalogue later still shows
  up — it lands at the bottom of the unranked pile rather than needing a
  migration. Called once at mount, not on every reload.
  """
  def ensure_seeded(user) when user in @users do
    Repo.transaction(fn ->
      ensure_dividers(user)
      ensure_rankings(user)
      :ok
    end)
  end

  defp ensure_dividers(user) do
    existing = Repo.all(from d in Divider, where: d.user == ^user, select: d.tier)
    missing = Divider.tiers() -- existing

    if missing != [] do
      # A fresh board: the bars go above every sketch, in tier order, and the
      # unranked pile keeps the order it already had underneath them.
      slots = slots(user)
      offset = length(missing)

      shifted = Enum.with_index(slots, fn slot, index -> {slot, index + offset} end)

      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      rows =
        Divider.tiers()
        |> Enum.filter(&(&1 in missing))
        |> Enum.with_index(fn tier, index ->
          %{
            user: user,
            tier: tier,
            position: index,
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(Divider, rows)
      persist_positions(shifted)
      # The eight new bars go in at 0..n; anything that was already there is
      # now below them, and sort_dividers puts a partially-seeded board back
      # into tier order.
      sort_dividers(user)
    end
  end

  # Tier bars must appear in S..unranked order. Reachable only when a board was
  # seeded, then the catalogue gained a tier — cheap insurance, not a hot path.
  defp sort_dividers(user) do
    slots = slots(user)
    rank = Enum.with_index(Divider.tiers()) |> Map.new()

    divider_positions =
      slots |> Enum.filter(&(&1.kind == :divider)) |> Enum.map(& &1.position) |> Enum.sort()

    ordered_tiers =
      slots
      |> Enum.filter(&(&1.kind == :divider))
      |> Enum.sort_by(&Map.fetch!(rank, &1.tier))

    ordered_tiers
    |> Enum.zip(divider_positions)
    |> persist_positions()
  end

  defp ensure_rankings(user) do
    ranked =
      Repo.all(from r in Ranking, where: r.user == ^user, select: r.sketch_id) |> MapSet.new()

    missing =
      Repo.all(
        from s in Sketch,
          order_by: [asc: s.season, asc: s.episode, asc: s.position, asc: s.id],
          select: s.id
      )
      |> Enum.reject(&MapSet.member?(ranked, &1))

    if missing != [] do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      next = next_position(user)

      rows =
        Enum.with_index(missing, fn sketch_id, index ->
          %{
            user: user,
            sketch_id: sketch_id,
            position: next + index,
            notes: "",
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(Ranking, rows)
    end
  end

  defp next_position(user) do
    ranking_max = Repo.one(from r in Ranking, where: r.user == ^user, select: max(r.position))
    divider_max = Repo.one(from d in Divider, where: d.user == ^user, select: max(d.position))

    [ranking_max, divider_max]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> 0
      values -> Enum.max(values) + 1
    end
  end

  # ------------------------------------------------------------------ board --

  @doc """
  One person's whole board, top to bottom, with each sketch's tier resolved from
  the bar above it.

  Entries are maps carrying `:id` (the string the browser drags), `:kind`,
  `:tier` and, for a sketch, `:sketch` and `:notes`. `:rank` is the sketch's
  1-based place within its tier.
  """
  def board(user) when user in @users do
    sketches =
      Repo.all(from(s in Sketch)) |> Map.new(&{&1.id, &1})

    rankings = Repo.all(from r in Ranking, where: r.user == ^user)
    dividers = Repo.all(from d in Divider, where: d.user == ^user)

    (Enum.map(dividers, fn divider ->
       %{
         id: "d-" <> divider.tier,
         kind: :divider,
         tier: divider.tier,
         position: divider.position,
         draggable?: divider.tier != "S"
       }
     end) ++
       Enum.map(rankings, fn ranking ->
         %{
           id: "s-" <> Integer.to_string(ranking.sketch_id),
           kind: :sketch,
           position: ranking.position,
           sketch: Map.fetch!(sketches, ranking.sketch_id),
           notes: ranking.notes,
           draggable?: true
         }
       end))
    |> Enum.sort_by(& &1.position)
    |> assign_tiers()
  end

  # One pass down the list carrying the last bar seen. "S" is the default rather
  # than nil: the S bar is pinned to index 0, so nothing should sit above it,
  # and if something ever did, top of the list is the honest reading.
  defp assign_tiers(entries) do
    {rows, _tier, _rank} =
      Enum.reduce(entries, {[], "S", 0}, fn
        %{kind: :divider} = entry, {acc, _tier, _rank} ->
          {[entry | acc], entry.tier, 0}

        %{kind: :sketch} = entry, {acc, tier, rank} ->
          {[Map.merge(entry, %{tier: tier, rank: rank + 1}) | acc], tier, rank + 1}
      end)

    Enum.reverse(rows)
  end

  @doc "How many sketches sit in each tier, keyed by tier."
  def tier_counts(entries) do
    entries
    |> Enum.filter(&(&1.kind == :sketch))
    |> Enum.frequencies_by(& &1.tier)
  end

  # ------------------------------------------------------------------ moves --

  @doc """
  Moves `drag_id` so it sits immediately after `after_id`, or at the top of the
  list when `after_id` is nil.

  Expressed against a neighbour rather than an index on purpose: the browser may
  be showing a filtered list, and a neighbour still means the same thing when
  rows are hidden.

  Refuses (`:error`) an unknown id, the pinned `S` bar, and a divider that would
  cross another — tier bars keep S..unranked order whatever the client sends.
  """
  def move(user, drag_id, after_id) when user in @users do
    with {:ok, dragged} <- decode_id(drag_id),
         :ok <- movable(dragged) do
      slots = slots(user)

      with {:ok, index} <- index_of(slots, dragged),
           {:ok, target} <- target_index(slots, after_id) do
        {entry, rest} = List.pop_at(slots, index)
        # Removing the dragged row shifts everything below it up by one.
        target = if target > index, do: target - 1, else: target
        reorder(user, entry, rest, clamp(rest, entry, target))
      end
    end
  end

  @doc """
  Moves a sketch to the **bottom of a tier**: immediately above the next tier's
  bar, or the end of the list for `unranked`.

  This is what dropping a sketch on a tier letter does, so a sketch can cross
  four hundred rows in one gesture instead of a scroll-and-drag. The bottom is a
  choice, not an accident — landing at the top would put every new arrival above
  the sketches already ranked there, and a person filling a tier in order would
  fight that on every drop.

  Sketches only: a tier bar has its own drag and its own clamping in `move/3`.
  `:error` for an unknown id, a divider id, or a tier outside `Divider.tiers/0`.
  """
  def move_to_tier(user, drag_id, tier) when user in @users do
    with {:ok, {:sketch, _} = dragged} <- decode_id(drag_id),
         true <- tier in Divider.tiers(),
         slots = slots(user),
         {:ok, index} <- index_of(slots, dragged) do
      {entry, rest} = List.pop_at(slots, index)
      reorder(user, entry, rest, tier_end(rest, tier))
    else
      _ -> :error
    end
  end

  # Where "the bottom of this tier" is in `rest`, the list with the dragged row
  # already taken out: just above the next bar, or past the last row.
  defp tier_end(rest, tier) do
    tiers = Divider.tiers()
    rank = Enum.find_index(tiers, &(&1 == tier))

    case Enum.at(tiers, rank + 1) do
      nil -> length(rest)
      following -> divider_index(rest, following)
    end
  end

  # The shared tail of every move: put `entry` at `target`, renumber, tell the
  # person's other tablet.
  defp reorder(user, entry, rest, target) do
    rest
    |> List.insert_at(target, entry)
    |> Enum.with_index(fn slot, position -> {slot, position} end)
    |> persist_positions()

    broadcast_user(user)
    :ok
  end

  defp movable({:divider, "S"}), do: :error
  defp movable(_), do: :ok

  defp index_of(slots, key) do
    case Enum.find_index(slots, &(slot_key(&1) == key)) do
      nil -> :error
      index -> {:ok, index}
    end
  end

  # nil means "put it at the very top", which is index 0.
  defp target_index(_slots, nil), do: {:ok, 0}

  defp target_index(slots, after_id) do
    with {:ok, key} <- decode_id(after_id),
         {:ok, index} <- index_of(slots, key) do
      {:ok, index + 1}
    end
  end

  # A sketch may go anywhere below the pinned S bar. A tier bar may not cross
  # another tier bar, so its window is between its canonical neighbours.
  defp clamp(_rest, %{kind: :sketch}, target), do: max(target, 1)

  defp clamp(rest, %{kind: :divider, tier: tier}, target) do
    tiers = Divider.tiers()
    rank = Enum.find_index(tiers, &(&1 == tier))

    lower =
      case Enum.at(tiers, rank - 1) do
        nil -> 0
        previous -> divider_index(rest, previous) + 1
      end

    upper =
      case Enum.at(tiers, rank + 1) do
        nil -> length(rest)
        following -> divider_index(rest, following)
      end

    target |> max(lower) |> min(upper)
  end

  defp divider_index(slots, tier) do
    Enum.find_index(slots, &(slot_key(&1) == {:divider, tier})) || length(slots)
  end

  defp slot_key(%{kind: :divider, tier: tier}), do: {:divider, tier}
  defp slot_key(%{kind: :sketch, sketch_id: sketch_id}), do: {:sketch, sketch_id}

  @doc """
  Parses a row id off the wire. `{:sketch, id}` / `{:divider, tier}`, or
  `:error` — never a raise, and never `String.to_atom` on client input.
  """
  def decode_id("s-" <> rest) do
    case Integer.parse(rest) do
      {id, ""} -> {:ok, {:sketch, id}}
      _ -> :error
    end
  end

  def decode_id("d-" <> tier) do
    if tier in Divider.tiers(), do: {:ok, {:divider, tier}}, else: :error
  end

  def decode_id(_), do: :error

  # The ordered sequence as bare rows: enough to reorder, no sketch bodies.
  defp slots(user) do
    dividers =
      Repo.all(from d in Divider, where: d.user == ^user, select: {d.id, d.tier, d.position})

    rankings =
      Repo.all(from r in Ranking, where: r.user == ^user, select: {r.id, r.sketch_id, r.position})

    (Enum.map(dividers, fn {id, tier, position} ->
       %{kind: :divider, row_id: id, tier: tier, position: position}
     end) ++
       Enum.map(rankings, fn {id, sketch_id, position} ->
         %{kind: :sketch, row_id: id, sketch_id: sketch_id, position: position}
       end))
    |> Enum.sort_by(& &1.position)
  end

  @doc false
  # Takes `{slot, new_position}` pairs — the slot still carrying the position it
  # has in the database, so the comparison below is old against new. Rewriting
  # `slot.position` before calling this makes every row look unchanged and
  # silently writes nothing.
  #
  # Only the rows that actually shifted are written. A move near the bottom of a
  # four-hundred-row list touches a handful; a move to the top touches the lot.
  defp persist_positions(pairs) do
    Repo.transaction(fn ->
      Enum.each(pairs, fn {slot, position} ->
        if slot.position != position do
          query =
            case slot.kind do
              :divider -> from(d in Divider, where: d.id == ^slot.row_id)
              :sketch -> from(r in Ranking, where: r.id == ^slot.row_id)
            end

          Repo.update_all(query, set: [position: position])
        end
      end)
    end)
  end

  # ------------------------------------------------------------- catalogue --

  @doc """
  Brings each sketch's description in line with `Taskmaster.Wkuk.Catalog`,
  **only for rows nobody has edited**.

  "Edited" is `updated_at != inserted_at`: the seed writes both with the same
  timestamp and every edit from the screen moves the second one. That is
  conservative — changing a row's YouTube link also counts, so its description is
  left as it is — and it means a correction someone typed is never overwritten by
  a later catalogue revision.

  Called by migration 9. Returns how many rows it changed.
  """
  def refresh_unedited_descriptions do
    Enum.reduce(Taskmaster.Wkuk.Catalog.all(), 0, fn sketch, changed ->
      {count, _} =
        Repo.update_all(
          from(s in Sketch,
            where:
              s.season == ^sketch.season and s.episode == ^sketch.episode and
                s.position == ^sketch.position and s.updated_at == s.inserted_at and
                s.description != ^sketch.description
          ),
          set: [description: sketch.description]
        )

      changed + count
    end)
  end

  # ------------------------------------------------------------------ edits --

  @doc "One sketch, or nil. `Repo.get/2` — the id comes off the wire."
  def get_sketch(id) when is_integer(id), do: Repo.get(Sketch, id)

  @doc """
  Edits the shared half of a sketch: `description` and `youtube_url`. Broadcasts
  on the shared topic, so the other person's open board picks it up.
  """
  def update_sketch(id, attrs) when is_integer(id) do
    case Repo.get(Sketch, id) do
      nil ->
        :error

      sketch ->
        sketch
        |> Sketch.changeset(attrs)
        |> Repo.update()
        |> tap(fn
          {:ok, _} -> broadcast_shared()
          _ -> :ok
        end)
    end
  end

  @doc """
  Edits one person's private notes on a sketch. Broadcasts on that person's
  topic only — the other board has different notes and does not care.
  """
  def update_notes(user, sketch_id, notes) when user in @users and is_integer(sketch_id) do
    case Repo.get_by(Ranking, user: user, sketch_id: sketch_id) do
      nil ->
        :error

      ranking ->
        ranking
        |> Ranking.changeset(%{notes: notes})
        |> Repo.update()
        |> tap(fn
          {:ok, _} -> broadcast_user(user)
          _ -> :ok
        end)
    end
  end

  @doc "One person's notes on one sketch, or \"\"."
  def notes(user, sketch_id) when user in @users and is_integer(sketch_id) do
    case Repo.get_by(Ranking, user: user, sketch_id: sketch_id) do
      nil -> ""
      ranking -> ranking.notes
    end
  end
end
