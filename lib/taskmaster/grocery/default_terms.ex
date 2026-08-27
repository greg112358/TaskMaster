defmodule Taskmaster.Grocery.DefaultTerms do
  @moduledoc """
  The grocery words the board knows out of the box.

  Kept deliberately small: things a household actually buys, not a produce
  encyclopedia. An unknown word costs one tap — the board asks which list, and
  never asks again — whereas a long tail of obscure entries earns nothing and
  gives short fragments more chances to match the wrong thing.

  Written as explicit strings, not `~w`. `~w` splits on an escaped space exactly
  as on a real one, so `~w(hot\\ dog)` is `["hot", "dog"]` — which silently
  shredded every multi-word term here and put *hot sauce* on the red list.

  Seed data only: migration 5 copies this into `grocery_terms` and migration 6
  re-seeds it. After that the table is the source of truth, so **editing this
  list does nothing to an existing database.**
  """

  @meat_dairy [
    "milk",
    "buttermilk",
    "cream",
    "heavy cream",
    "sour cream",
    "whipped cream",
    "half and half",
    "cream cheese",
    "cottage cheese",
    "cheese",
    "cheddar",
    "mozzarella",
    "parmesan",
    "swiss",
    "feta",
    "goat cheese",
    "string cheese",
    "butter",
    "yogurt",
    "ice cream",
    "egg",
    "beef",
    "ground beef",
    "steak",
    "roast beef",
    "corned beef",
    "brisket",
    "ribs",
    "pork",
    "pork chops",
    "bacon",
    "ham",
    "sausage",
    "hot dog",
    "pepperoni",
    "salami",
    "prosciutto",
    "deli meat",
    "lunch meat",
    "chicken",
    "chicken breast",
    "chicken thighs",
    "ground chicken",
    "turkey",
    "ground turkey",
    "lamb",
    "fish",
    "salmon",
    "tuna",
    "tilapia",
    "cod",
    "shrimp",
    "crab",
    "lobster",
    "scallops"
  ]

  @produce [
    "apple",
    "banana",
    "orange",
    "lemon",
    "lime",
    "grapefruit",
    "grapes",
    "strawberries",
    "blueberries",
    "raspberries",
    "blackberries",
    "berries",
    "mango",
    "pineapple",
    "watermelon",
    "cantaloupe",
    "peach",
    "pear",
    "plum",
    "cherries",
    "kiwi",
    "avocado",
    "lettuce",
    "romaine",
    "spinach",
    "kale",
    "arugula",
    "salad",
    "cabbage",
    "broccoli",
    "cauliflower",
    "brussels sprouts",
    "asparagus",
    "green beans",
    "peas",
    "corn",
    "carrots",
    "celery",
    "cucumber",
    "zucchini",
    "squash",
    "butternut squash",
    "eggplant",
    "tomato",
    "potato",
    "sweet potato",
    "onion",
    "red onion",
    "green onion",
    "scallions",
    "shallot",
    "leek",
    "garlic",
    "ginger",
    "mushrooms",
    "bell pepper",
    "jalapeno",
    "radish",
    "beet",
    "cilantro",
    "parsley",
    "basil",
    "mint",
    "rosemary",
    "thyme",
    "dill"
  ]

  # Only the traps: names that contain a dairy or produce word but belong
  # nowhere near those lists. Longest-match puts them right.
  @other [
    "peanut butter",
    "almond butter",
    "orange juice",
    "apple juice"
  ]

  @doc """
  Every built-in term as `{name, category}`, lowercased and deduplicated.
  """
  def all do
    for {terms, category} <- [
          {@meat_dairy, "meat_dairy"},
          {@produce, "produce"},
          {@other, "other"}
        ],
        term <- terms do
      {String.downcase(term), category}
    end
    |> Enum.uniq_by(&elem(&1, 0))
  end
end
