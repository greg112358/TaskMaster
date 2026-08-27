defmodule Taskmaster.Grocery.DictionaryTest do
  use Taskmaster.DataCase

  alias Taskmaster.Grocery
  alias Taskmaster.Grocery.Dictionary

  describe "the built-in vocabulary" do
    test "is small on purpose — household words, not an encyclopedia" do
      count = Dictionary.count()
      assert count > 80 and count < 160
    end

    test "leaves out words nobody writes on a grocery list" do
      for obscure <- ~w(anaheim ancho rambutan soursop epazote lovage guajillo) do
        assert Dictionary.category_for(obscure) == :unknown,
               "#{obscure} should not ship in the dictionary"
      end
    end

    test "categorises the words the old hardcoded lists did" do
      assert Dictionary.category_for("milk") == {:ok, "meat_dairy"}
      assert Dictionary.category_for("broccoli") == {:ok, "produce"}
    end
  end

  describe "category_for/1" do
    test "is case and whitespace insensitive" do
      assert Dictionary.category_for("  MILK  ") == {:ok, "meat_dairy"}
      assert Dictionary.category_for("Green   Beans") == {:ok, "produce"}
    end

    test "matches a known word inside a longer name" do
      assert Dictionary.category_for("whole milk") == {:ok, "meat_dairy"}
      assert Dictionary.category_for("organic baby spinach") == {:ok, "produce"}
    end

    test "prefers the longest match, so a substring cannot hijack it" do
      # "corn" is produce and "corned beef" is meat & dairy; the longer term wins
      assert Dictionary.category_for("corn") == {:ok, "produce"}
      assert Dictionary.category_for("corned beef") == {:ok, "meat_dairy"}
      # "butter" is dairy; "peanut butter" is longer, so it wins.
      assert Dictionary.category_for("butter") == {:ok, "meat_dairy"}
      assert Dictionary.category_for("peanut butter") == {:ok, "other"}
    end

    test "only matches whole words, so fragments cannot hijack a name" do
      # "ham" and "sole" are real terms; "graham" and "casserole" merely
      # contain them.
      assert Dictionary.category_for("ham") == {:ok, "meat_dairy"}
      assert Dictionary.category_for("graham crackers") == :unknown
      assert Dictionary.category_for("casserole dish") == :unknown
    end

    test "keeps multi-word terms intact" do
      assert Dictionary.category_for("hot dog") == {:ok, "meat_dairy"}
      assert Dictionary.category_for("green beans") == {:ok, "produce"}
      assert Dictionary.category_for("sweet potato") == {:ok, "produce"}
      assert Dictionary.category_for("ice cream") == {:ok, "meat_dairy"}
    end

    test "matches either number, whichever way the term is stored" do
      # stored plural, asked singular
      assert Dictionary.category_for("carrot") == {:ok, "produce"}
      assert Dictionary.category_for("grape") == {:ok, "produce"}
      assert Dictionary.category_for("strawberry") == {:ok, "produce"}
      assert Dictionary.category_for("green bean") == {:ok, "produce"}

      # stored singular, asked plural
      assert Dictionary.category_for("tomatoes") == {:ok, "produce"}
      assert Dictionary.category_for("potatoes") == {:ok, "produce"}
      assert Dictionary.category_for("eggs") == {:ok, "meat_dairy"}
      assert Dictionary.category_for("onions") == {:ok, "produce"}
    end

    test "does not mistake a word ending in s for a plural" do
      assert Dictionary.category_for("asparagus") == {:ok, "produce"}
      assert Dictionary.category_for("swiss") == {:ok, "meat_dairy"}
    end

    test "keeps pantry lookalikes off the dairy and produce lists" do
      assert Dictionary.category_for("peanut butter") == {:ok, "other"}
      assert Dictionary.category_for("orange juice") == {:ok, "other"}
    end

    test "does not let a multi-word term's fragments match on their own" do
      # Regression: ~w() split "hot dog" into "hot" and "dog", after which
      # anything containing "hot" landed on the red list.
      assert Dictionary.category_for("hot sauce") == :unknown
    end

    test "does not know a word nobody taught it" do
      assert Dictionary.category_for("quinoa") == :unknown
      refute Dictionary.known?("quinoa")
    end

    test "treats blank input as unknown" do
      assert Dictionary.category_for("") == :unknown
      assert Dictionary.category_for("   ") == :unknown
      assert Dictionary.category_for(nil) == :unknown
    end
  end

  describe "category_for!/1" do
    test "falls back to everything else where there is nobody to ask" do
      assert Dictionary.category_for!("quinoa") == "other"
      assert Dictionary.category_for!("milk") == "meat_dairy"
    end
  end

  describe "learn/2" do
    test "teaches a new word" do
      assert {:ok, _} = Dictionary.learn("Quinoa", "other")
      assert Dictionary.category_for("quinoa") == {:ok, "other"}
    end

    test "stores the normalised name" do
      {:ok, term} = Dictionary.learn("  Sourdough  BREAD ", "other")
      assert term.name == "sourdough bread"
    end

    test "re-teaching moves an existing word rather than failing" do
      {:ok, _} = Dictionary.learn("tofu", "other")
      assert {:ok, _} = Dictionary.learn("tofu", "produce")

      assert Dictionary.category_for("tofu") == {:ok, "produce"}
      assert Enum.count(Dictionary.list(), &(&1.name == "tofu")) == 1
    end

    test "rejects a category that is not one of the three lists" do
      assert {:error, changeset} = Dictionary.learn("tofu", "frozen")
      assert "is invalid" in errors_on(changeset).category
    end
  end

  describe "forget/1" do
    test "removes a taught word" do
      {:ok, _} = Dictionary.learn("quinoa", "other")

      assert {:ok, _} = Dictionary.forget("quinoa")
      assert Dictionary.category_for("quinoa") == :unknown
    end

    test "removes a built-in word too" do
      assert {:ok, _} = Dictionary.forget("milk")
      assert Dictionary.category_for("milk") == :unknown
    end

    test "is unbothered by a word it never knew" do
      assert Dictionary.forget("nonsense") == :error
    end
  end

  describe "suggest/2" do
    test "offers nothing for an empty query" do
      assert Dictionary.suggest("") == []
      assert Dictionary.suggest("   ") == []
    end

    test "ranks words starting with the query first" do
      names = Dictionary.suggest("milk") |> Enum.map(& &1.name)

      assert "milk" == hd(names)
    end

    test "matches inside a word as well as at the start" do
      assert Dictionary.suggest("hicken") |> Enum.any?(&(&1.name == "chicken"))
    end

    test "does not offer a word that was deleted" do
      {:ok, _} = Dictionary.forget("milk")

      refute Dictionary.suggest("milk") |> Enum.any?(&(&1.name == "milk"))
    end

    test "honours the limit" do
      assert Dictionary.suggest("e", 3) |> length() == 3
    end

    test "carries the category so the UI can colour each row" do
      assert [%{category: "meat_dairy"} | _] = Dictionary.suggest("milk")
    end
  end

  describe "adding an item" do
    test "uses the dictionary to pick the list" do
      {:ok, item} = Grocery.add_item("whole milk")
      assert item.category == "meat_dairy"
    end

    test "respects an explicitly chosen category" do
      {:ok, item} = Grocery.add_item("milk", "other")
      assert item.category == "other"
    end

    test "puts an unknown word on the everything-else list" do
      {:ok, item} = Grocery.add_item("quinoa")
      assert item.category == "other"
    end
  end
end
