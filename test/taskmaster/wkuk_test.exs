defmodule Taskmaster.WkukTest do
  use Taskmaster.DataCase

  alias Taskmaster.Wkuk
  alias Taskmaster.Wkuk.{Catalog, Divider}

  defp board_ids(user) do
    Wkuk.board(user) |> Enum.map(& &1.id)
  end

  defp tier_of(user, sketch_id) do
    Wkuk.board(user)
    |> Enum.find(&(&1.id == "s-" <> Integer.to_string(sketch_id)))
    |> Map.fetch!(:tier)
  end

  defp first_sketch_id(user) do
    Wkuk.board(user) |> Enum.find(&(&1.kind == :sketch)) |> Map.fetch!(:sketch) |> Map.fetch!(:id)
  end

  describe "the catalogue" do
    test "every sketch has a short description" do
      for sketch <- Catalog.all() do
        assert sketch.description != "", "#{sketch.title} has no description"
        assert String.length(sketch.description) <= 200, "#{sketch.title} is too long"
      end
    end

    test "keeps the wording the owner asked for" do
      by_title = Map.new(Catalog.all(), &{&1.title, &1.description})

      assert by_title["iPod Shuffle"] =~ "pregnancy test"
      assert by_title["Jerkocaust"] == "Nazis look for jerks"
    end
  end

  describe "refresh_unedited_descriptions/0" do
    # The seed writes inserted_at and updated_at with one timestamp, and an edit
    # moves updated_at. The test DB was seeded long ago, so an edit here already
    # differs; setting both explicitly keeps the test independent of that.
    defp age(sketch_id, opts) do
      Taskmaster.Repo.update_all(
        from(s in Taskmaster.Wkuk.Sketch, where: s.id == ^sketch_id),
        set: opts
      )
    end

    test "restores an unedited row and leaves an edited one alone" do
      [first, second | _] = Catalog.all()

      untouched =
        Taskmaster.Repo.get_by!(Taskmaster.Wkuk.Sketch,
          season: first.season,
          episode: first.episode,
          position: first.position
        )

      edited =
        Taskmaster.Repo.get_by!(Taskmaster.Wkuk.Sketch,
          season: second.season,
          episode: second.episode,
          position: second.position
        )

      stamp = ~N[2020-01-01 00:00:00]
      age(untouched.id, description: "first draft", inserted_at: stamp, updated_at: stamp)

      age(edited.id,
        description: "typed by a person",
        inserted_at: stamp,
        updated_at: ~N[2021-06-01 00:00:00]
      )

      assert Wkuk.refresh_unedited_descriptions() >= 1

      assert Wkuk.get_sketch(untouched.id).description == first.description
      assert Wkuk.get_sketch(edited.id).description == "typed by a person"
    end

    test "is a no-op once everything is current" do
      Wkuk.refresh_unedited_descriptions()
      assert Wkuk.refresh_unedited_descriptions() == 0
    end
  end

  describe "ensure_seeded/1" do
    test "puts every sketch below the unranked bar" do
      Wkuk.ensure_seeded("greg")
      entries = Wkuk.board("greg")

      dividers = Enum.filter(entries, &(&1.kind == :divider))
      sketches = Enum.filter(entries, &(&1.kind == :sketch))

      assert Enum.map(dividers, & &1.tier) == Divider.tiers()
      assert length(sketches) == Catalog.count()
      assert Enum.all?(sketches, &(&1.tier == "unranked"))
      assert Wkuk.tier_counts(entries) == %{"unranked" => Catalog.count()}
    end

    test "is idempotent" do
      Wkuk.ensure_seeded("greg")
      before = board_ids("greg")
      Wkuk.ensure_seeded("greg")

      assert board_ids("greg") == before
    end

    test "gives each person their own order" do
      Wkuk.ensure_seeded("greg")
      Wkuk.ensure_seeded("john")

      sketch_id = first_sketch_id("greg")
      assert :ok = Wkuk.move("greg", "s-#{sketch_id}", "d-S")

      assert tier_of("greg", sketch_id) == "S"
      assert tier_of("john", sketch_id) == "unranked"
    end
  end

  describe "move/3" do
    setup do
      Wkuk.ensure_seeded("greg")
      %{sketch_id: first_sketch_id("greg")}
    end

    test "ranks a sketch by dropping it under a tier bar", %{sketch_id: id} do
      assert :ok = Wkuk.move("greg", "s-#{id}", "d-C")
      assert tier_of("greg", id) == "C"
    end

    test "nil after puts a sketch at the top, still under the S bar", %{sketch_id: id} do
      assert :ok = Wkuk.move("greg", "s-#{id}", nil)

      assert Enum.take(board_ids("greg"), 2) == ["d-S", "s-#{id}"]
      assert tier_of("greg", id) == "S"
    end

    test "dragging a bar re-tiers every sketch it crosses", %{sketch_id: id} do
      assert :ok = Wkuk.move("greg", "s-#{id}", "d-S")
      assert tier_of("greg", id) == "S"

      # The A bar moves above the sketch, so the sketch is now in A.
      assert :ok = Wkuk.move("greg", "d-A", "d-S")
      assert tier_of("greg", id) == "A"
    end

    test "a bar cannot cross another bar" do
      before = board_ids("greg")

      # C is asked to land below E. It stops directly under B instead.
      assert :ok = Wkuk.move("greg", "d-C", "d-E")

      assert board_ids("greg") == before
    end

    test "the S bar is pinned", %{sketch_id: id} do
      assert :error = Wkuk.move("greg", "d-S", "d-F")
      assert :error = Wkuk.move("greg", "d-S", "s-#{id}")
      assert List.first(board_ids("greg")) == "d-S"
    end

    test "unknown ids are refused, not raised on", %{sketch_id: id} do
      assert :error = Wkuk.move("greg", "s-999999", nil)
      assert :error = Wkuk.move("greg", "nonsense", nil)
      assert :error = Wkuk.move("greg", "s-not-a-number", nil)
      assert :error = Wkuk.move("greg", "d-Z", nil)
      assert :error = Wkuk.move("greg", "s-#{id}", "s-999999")
    end

    test "positions stay dense after a move", %{sketch_id: id} do
      assert :ok = Wkuk.move("greg", "s-#{id}", "d-B")

      positions =
        Wkuk.board("greg")
        |> Enum.map(& &1.position)

      assert positions == Enum.to_list(0..(length(positions) - 1))
    end
  end

  describe "move_to_tier/3" do
    setup do
      Wkuk.ensure_seeded("greg")
      ids = Wkuk.board("greg") |> Enum.filter(&(&1.kind == :sketch)) |> Enum.map(& &1.sketch.id)
      %{ids: ids}
    end

    test "jumps a sketch straight to a tier from the bottom of the pile", %{ids: ids} do
      last = List.last(ids)

      assert :ok = Wkuk.move_to_tier("greg", "s-#{last}", "S")

      assert tier_of("greg", last) == "S"
      assert Enum.take(board_ids("greg"), 2) == ["d-S", "s-#{last}"]
    end

    test "lands at the bottom of the tier, under what is already there", %{ids: [a, b | _]} do
      assert :ok = Wkuk.move_to_tier("greg", "s-#{a}", "A")
      assert :ok = Wkuk.move_to_tier("greg", "s-#{b}", "A")

      # a arrived first, so it stays above b.
      assert Enum.slice(board_ids("greg"), 0, 5) == ["d-S", "d-A", "s-#{a}", "s-#{b}", "d-B"]
    end

    test "an empty tier still has a bottom", %{ids: [a | _]} do
      assert :ok = Wkuk.move_to_tier("greg", "s-#{a}", "D")

      assert tier_of("greg", a) == "D"
      assert Enum.slice(board_ids("greg"), 4, 3) == ["d-D", "s-#{a}", "d-E"]
    end

    test "unranked is the end of the list", %{ids: [a | _]} do
      assert :ok = Wkuk.move_to_tier("greg", "s-#{a}", "S")
      assert :ok = Wkuk.move_to_tier("greg", "s-#{a}", "unranked")

      assert tier_of("greg", a) == "unranked"
      assert List.last(board_ids("greg")) == "s-#{a}"
    end

    test "moving within a tier changes nothing else", %{ids: [a, b | _]} do
      assert :ok = Wkuk.move_to_tier("greg", "s-#{a}", "B")
      assert :ok = Wkuk.move_to_tier("greg", "s-#{b}", "B")
      assert :ok = Wkuk.move_to_tier("greg", "s-#{a}", "B")

      # a went to the bottom of B again, below b.
      assert Enum.slice(board_ids("greg"), 0, 6) == [
               "d-S",
               "d-A",
               "d-B",
               "s-#{b}",
               "s-#{a}",
               "d-C"
             ]
    end

    test "positions stay dense", %{ids: [a | _]} do
      assert :ok = Wkuk.move_to_tier("greg", "s-#{a}", "C")

      positions = Wkuk.board("greg") |> Enum.map(& &1.position)
      assert positions == Enum.to_list(0..(length(positions) - 1))
    end

    test "refuses dividers, junk ids and unknown tiers", %{ids: [a | _]} do
      assert :error = Wkuk.move_to_tier("greg", "d-A", "S")
      assert :error = Wkuk.move_to_tier("greg", "s-999999", "S")
      assert :error = Wkuk.move_to_tier("greg", "nonsense", "S")
      assert :error = Wkuk.move_to_tier("greg", "s-#{a}", "Z")
      assert :error = Wkuk.move_to_tier("greg", "s-#{a}", "")
    end

    test "is per person", %{ids: [a | _]} do
      Wkuk.ensure_seeded("john")
      assert :ok = Wkuk.move_to_tier("greg", "s-#{a}", "S")

      assert tier_of("john", a) == "unranked"
    end
  end

  describe "decode_id/1" do
    test "parses rather than converts" do
      assert {:ok, {:sketch, 12}} = Wkuk.decode_id("s-12")
      assert {:ok, {:divider, "S"}} = Wkuk.decode_id("d-S")
      assert :error = Wkuk.decode_id("s-12x")
      assert :error = Wkuk.decode_id("s-")
      assert :error = Wkuk.decode_id("d-nope")
      assert :error = Wkuk.decode_id("")
    end
  end

  describe "sharing" do
    setup do
      Wkuk.ensure_seeded("greg")
      Wkuk.ensure_seeded("john")
      %{sketch_id: first_sketch_id("greg")}
    end

    test "a description edit reaches both boards", %{sketch_id: id} do
      assert {:ok, _} = Wkuk.update_sketch(id, %{description: "nazis look for jerks"})

      for user <- Wkuk.users() do
        entry = Wkuk.board(user) |> Enum.find(&(&1.id == "s-#{id}"))
        assert entry.sketch.description == "nazis look for jerks"
      end
    end

    test "notes stay with one person", %{sketch_id: id} do
      assert {:ok, _} = Wkuk.update_notes("greg", id, "top five")

      assert Wkuk.notes("greg", id) == "top five"
      assert Wkuk.notes("john", id) == ""
    end

    test "a youtube_url that is not http is refused", %{sketch_id: id} do
      assert {:error, changeset} =
               Wkuk.update_sketch(id, %{youtube_url: "javascript:alert(1)"})

      assert "must be an http or https URL" in errors_on(changeset).youtube_url
      assert Wkuk.get_sketch(id).youtube_url == nil
    end

    test "a blank youtube_url clears the field", %{sketch_id: id} do
      assert {:ok, _} = Wkuk.update_sketch(id, %{youtube_url: "https://youtu.be/abc"})
      assert {:ok, sketch} = Wkuk.update_sketch(id, %{youtube_url: "   "})
      assert sketch.youtube_url == nil
    end

    test "a stale sketch id answers :error, it does not raise" do
      assert :error = Wkuk.update_sketch(999_999, %{description: "x"})
      assert :error = Wkuk.update_notes("greg", 999_999, "x")
    end
  end
end
