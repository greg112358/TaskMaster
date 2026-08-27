defmodule Taskmaster.Grocery.Dictionary do
  @moduledoc """
  What the board knows about grocery words: which list a word belongs on, what
  to suggest while somebody is typing, and how the family teaches it new words.

  The dictionary is the single source of truth for categorising. It starts life
  seeded from `Taskmaster.Grocery.DefaultTerms` (migration 5) and is edited from
  the Groceries screen thereafter — every term, built-in ones included, can be
  forgotten.

  ## Matching

  `category_for/1` answers in two steps:

    1. an exact match on the normalised name; failing that
    2. the **longest** known term appearing in the name **on word boundaries**.

  Step 2 is what lets "whole milk" land on the red list without anyone teaching
  it, and *longest* rather than first is what keeps "corned beef" out of produce
  when "corn" is also known.

  Word boundaries matter more than they look. A plain substring test makes "ham"
  match "graham crackers" and "sole" match "casserole" — silently, and with no
  way for anyone at the board to work out why the colour is wrong. Requiring
  whole words costs plurals ("tomatoes" no longer resolves via "tomato") and
  that is the right trade: an unrecognised word simply asks which list it goes
  on, and is never asked about again. A wrong guess just looks broken.

  Both steps are retried against a singular and a plural form of the name, so
  "carrot" finds the stored "carrots" and "tomatoes" finds the stored "tomato" —
  the dictionary stays small instead of carrying both spellings of everything.

  Anything no step matches is `:unknown`, which is the signal for the UI to ask.
  """

  import Ecto.Query

  alias Taskmaster.Grocery.Term
  alias Taskmaster.Repo

  @categories ~w(meat_dairy produce other)
  @topic "grocery_dictionary"

  @doc """
  Dictionary edits are broadcast so anything showing suggestions can refresh
  *after* the write lands — recomputing them optimistically leaves a
  just-forgotten word sitting in the list.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Taskmaster.PubSub, @topic)
  end

  defp broadcast do
    Phoenix.PubSub.broadcast(Taskmaster.PubSub, @topic, :dictionary_changed)
  end

  @doc "The category values a term may carry, in display order."
  def categories, do: @categories

  @doc """
  Names are matched, stored and compared in one canonical form: lowercase, with
  surrounding and repeated whitespace collapsed.
  """
  def normalize(nil), do: ""

  def normalize(name) do
    name
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  @doc """
  `{:ok, category}` for a name the board recognises, `:unknown` otherwise.
  """
  def category_for(name) do
    case matching_term(name) do
      nil -> :unknown
      term -> {:ok, term.category}
    end
  end

  @doc """
  The dictionary entry that decides where `name` goes, or `nil`.

  Not always the name itself: "whole milk" is decided by the entry "milk". The
  Groceries screen uses this so that holding an item offers to forget the word
  actually responsible for its colour, rather than a word that was never in the
  dictionary to begin with.
  """
  def matching_term(name) do
    case normalize(name) do
      "" ->
        nil

      normalized ->
        normalized
        |> variants()
        |> Enum.find_value(fn candidate ->
          exact_match(candidate) || longest_contained_match(candidate)
        end)
    end
  end

  # Plurals, without doubling the size of the dictionary. The stored term is
  # whichever form people write ("carrots", "tomato"), and a query that differs
  # only in number is retried the other way round. A nonsense variant simply
  # fails to match, so guessing wrong here costs nothing.
  defp variants(normalized) do
    [normalized, singularize(normalized), pluralize_last(normalized)]
    |> Enum.uniq()
  end

  defp singularize(name) do
    name |> String.split(" ") |> Enum.map_join(" ", &singular/1)
  end

  defp singular(word) do
    cond do
      String.ends_with?(word, "ies") and String.length(word) > 4 ->
        String.replace_suffix(word, "ies", "y")

      # "ss" and "us" endings are not plurals: swiss, asparagus, hummus.
      String.ends_with?(word, ["ss", "us"]) ->
        word

      String.ends_with?(word, "es") and String.length(word) > 4 ->
        String.replace_suffix(word, "es", "")

      String.ends_with?(word, "s") and String.length(word) > 3 ->
        String.replace_suffix(word, "s", "")

      true ->
        word
    end
  end

  # Only the last word: grocery names carry their number on the head noun
  # ("green bean" -> "green beans"), never on the modifier.
  defp pluralize_last(name) do
    case String.split(name, " ") do
      [] -> name
      words -> words |> List.update_at(-1, &plural/1) |> Enum.join(" ")
    end
  end

  defp plural(word) do
    cond do
      String.ends_with?(word, "s") -> word
      String.ends_with?(word, "y") -> String.replace_suffix(word, "y", "ies")
      true -> word <> "s"
    end
  end

  @doc """
  Like `category_for/1` but always answers, falling back to the "everything
  else" list. Used where there is nobody to ask — the voice command in
  particular, which cannot put up a dialog.
  """
  def category_for!(name) do
    case category_for(name) do
      {:ok, category} -> category
      :unknown -> "other"
    end
  end

  @doc "Whether the board already knows this name."
  def known?(name), do: category_for(name) != :unknown

  @doc """
  Terms to offer while somebody is typing. Names *starting* with the query come
  first, then shorter names before longer ones, so "mil" offers "milk" ahead of
  "condensed milk".
  """
  def suggest(query, limit \\ 6) do
    case normalize(query) do
      "" ->
        []

      normalized ->
        Repo.all(
          from t in Term,
            where: fragment("instr(?, ?) > 0", t.name, ^normalized),
            order_by: [
              asc: fragment("instr(?, ?)", t.name, ^normalized),
              asc: fragment("length(?)", t.name),
              asc: t.name
            ],
            limit: ^limit
        )
    end
  end

  @doc """
  Teaches the board a word. Re-teaching an existing word moves it to the new
  category rather than failing.
  """
  def learn(name, category) do
    %Term{}
    |> Term.changeset(%{name: name, category: category})
    |> Repo.insert(
      on_conflict: [set: [category: category, updated_at: NaiveDateTime.utc_now(:second)]],
      conflict_target: :name
    )
    |> tap(fn
      {:ok, _} -> broadcast()
      _ -> :ok
    end)
  end

  @doc """
  Forgets a word. Returns `{:ok, term}`, or `:error` when it was not known —
  which is not worth surfacing, since the caller wanted it gone either way.
  """
  def forget(name) do
    case Repo.get_by(Term, name: normalize(name)) do
      nil ->
        :error

      term ->
        term
        |> Repo.delete()
        |> tap(fn
          {:ok, _} -> broadcast()
          _ -> :ok
        end)
    end
  end

  @doc "Every known term, alphabetically. Mostly for tests and inspection."
  def list do
    Repo.all(from t in Term, order_by: t.name)
  end

  def count, do: Repo.aggregate(Term, :count)

  defp exact_match(normalized) do
    Repo.one(from t in Term, where: t.name == ^normalized)
  end

  # Padding both sides with a space turns a substring test into a whole-word
  # one: " graham crackers " does not contain " ham ". Names are normalised to
  # single spaces, so this is sufficient. instr/2 rather than LIKE, so a name
  # containing % or _ cannot behave as a wildcard.
  defp longest_contained_match(normalized) do
    Repo.one(
      from t in Term,
        where: fragment("instr(' ' || ? || ' ', ' ' || ? || ' ') > 0", ^normalized, t.name),
        order_by: [desc: fragment("length(?)", t.name)],
        limit: 1
    )
  end
end
