defmodule Taskmaster.Grocery.Categorizer do
  @meat_dairy ~w(
    milk cheese butter cream yogurt beef chicken pork lamb turkey bacon ham sausage
    steak eggs egg meat fish salmon tuna shrimp crab lobster veal duck goose bison venison
    mozzarella cheddar parmesan brie gouda ricotta cottage swiss provolone colby
    muenster havarti gruyere fontina mascarpone camembert feta halloumi paneer
    monterey pepper\ jack american velveeta queso
    tilapia cod catfish trout bass perch walleye mahi sardine anchovy herring mackerel
    swordfish halibut snapper grouper flounder sole clam mussel oyster scallop squid
    calamari octopus crawfish prawn ceviche lox gravlax
    pepperoni salami prosciutto capicola pancetta chorizo bratwurst kielbasa liverwurst
    bologna hot\ dog jerky corned\ beef pastrami roast\ beef ground\ beef ground\ turkey
    ground\ pork ribs tenderloin sirloin ribeye filet brisket flank skirt chuck roast
    drumstick thigh breast wing giblet liver kidney tongue tripe oxtail
    buttermilk kefir whey casein ghee lard tallow suet
    half\ and\ half whipping\ cream sour\ cream cream\ cheese ice\ cream
    custard pudding gelato frozen\ yogurt
    eggnog condensed\ milk evaporated\ milk powdered\ milk goat\ milk oat\ milk
    almond\ milk soy\ milk coconut\ milk
  )

  @produce ~w(
    apple banana orange lettuce tomato potato onion carrot broccoli pepper spinach
    cucumber celery garlic avocado lemon lime berry berries grapes grape mango pineapple
    watermelon cantaloupe honeydew peach pear plum cherry strawberry blueberry raspberry
    blackberry kiwi papaya coconut pomegranate fig date apricot nectarine tangerine
    grapefruit zucchini squash eggplant cabbage kale arugula radish turnip beet
    asparagus artichoke corn peas beans mushroom cilantro parsley basil mint dill
    rosemary thyme oregano ginger jalapeno habanero serrano poblano
    clementine mandarin kumquat lychee dragonfruit starfruit passionfruit guava
    persimmon jackfruit durian rambutan longan plantain breadfruit soursop
    boysenberry elderberry gooseberry cranberry currant acai goji mulberry
    blood\ orange cara\ cara navel satsuma tangelo ugli
    romaine iceberg bibb butterhead endive radicchio watercress chard
    collard bok\ choy napa fennel leek scallion shallot chive
    green\ onion ramp spring\ onion
    sweet\ potato yam parsnip rutabaga celeriac jicama taro cassava
    daikon kohlrabi sunchoke horseradish wasabi turmeric galangal
    lemongrass tamarind
    snow\ pea snap\ pea edamame lima fava chickpea lentil
    green\ bean wax\ bean kidney\ bean black\ bean pinto\ bean navy\ bean
    okra brussels\ sprout cauliflower broccolini rapini
    pumpkin acorn\ squash butternut spaghetti\ squash delicata kabocha
    bell\ pepper banana\ pepper cherry\ pepper scotch\ bonnet ghost\ pepper
    cayenne chipotle ancho guajillo pasilla anaheim hatch
    portobello shiitake oyster\ mushroom chanterelle morel porcini enoki
    cremini maitake truffle
    sage tarragon chervil marjoram lemon\ balm sorrel lovage epazote
    curry\ leaf bay\ leaf lavender chamomile
    sprout microgreen wheatgrass alfalfa bean\ sprout
  )

  def categorize(item_name) do
    name = String.downcase(item_name)

    cond do
      matches?(name, @meat_dairy) -> "meat_dairy"
      matches?(name, @produce) -> "produce"
      true -> "other"
    end
  end

  defp matches?(name, keywords) do
    Enum.any?(keywords, fn keyword -> String.contains?(name, keyword) end)
  end
end
