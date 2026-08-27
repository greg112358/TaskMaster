defmodule TaskmasterWeb.GroceryDictionaryTest do
  use TaskmasterWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Taskmaster.Grocery
  alias Taskmaster.Grocery.Dictionary

  defp groceries(conn) do
    {:ok, view, _html} = live(conn, "/")
    view = isolate_view(view)

    view |> element("button", "Groceries") |> render_click()
    view
  end

  defp type(view, text) do
    view
    |> form("#grocery-form", %{"name" => text})
    |> render_change()
  end

  defp submit(view, text) do
    view
    |> form("#grocery-form", %{"name" => text})
    |> render_submit()

    # The component hands writes to AppLive as a message; rendering waits for it.
    render(view)
  end

  # The suggestion row itself, as distinct from its red x.
  defp suggestion(view, name) do
    element(
      view,
      "#grocery-suggestions button[phx-click='use_suggestion'][phx-value-name='#{name}']"
    )
  end

  defp forget_x(view, name) do
    element(view, "#grocery-suggestions button[phx-click='ask_forget'][phx-value-name='#{name}']")
  end

  # Long press. The hook reaches AppLive, which hands it to the component via
  # send_update — asynchronous, so the dialog is only in the *next* render.
  defp hold(view, name) do
    render_hook(view, "hold_grocery_item", %{"name" => name})
    render(view)
  end

  # A dictionary edit travels component -> AppLive -> PubSub -> AppLive ->
  # component. Each hop is a message, and a render only drains what was already
  # queued, so the DOM has settled only once they have all been through.
  defp settle(view) do
    Enum.each(1..3, fn _ -> render(view) end)
    render(view)
  end

  describe "adding a word the board knows" do
    test "files it without asking", %{conn: conn} do
      view = groceries(conn)

      html = submit(view, "milk")

      refute html =~ "Which list?"
      assert [%{name: "milk", category: "meat_dairy"}] = Grocery.list_items()
    end

    test "recognises it inside a longer name", %{conn: conn} do
      view = groceries(conn)

      submit(view, "whole milk")

      assert [%{name: "whole milk", category: "meat_dairy"}] = Grocery.list_items()
    end
  end

  describe "adding a word the board does not know" do
    test "asks which list it goes on instead of guessing", %{conn: conn} do
      view = groceries(conn)

      html = submit(view, "quinoa")

      assert html =~ "Which list?"
      assert html =~ "quinoa"
      assert Grocery.list_items() == []
    end

    test "answering files the item and teaches the word", %{conn: conn} do
      view = groceries(conn)
      submit(view, "quinoa")

      view
      |> element("#categorize-dialog button", "Everything Else")
      |> render_click()

      render(view)

      assert [%{name: "quinoa", category: "other"}] = Grocery.list_items()
      assert Dictionary.category_for("quinoa") == {:ok, "other"}
    end

    test "so the same word is never asked about twice", %{conn: conn} do
      view = groceries(conn)
      submit(view, "quinoa")
      view |> element("#categorize-dialog button", "Produce") |> render_click()
      render(view)

      html = submit(view, "quinoa")

      refute html =~ "Which list?"
      assert [_, %{name: "quinoa", category: "produce"}] = Grocery.list_items()
    end

    test "cancelling adds nothing and teaches nothing", %{conn: conn} do
      view = groceries(conn)
      submit(view, "quinoa")

      view |> element("#categorize-dialog button", "Cancel") |> render_click()

      refute render(view) =~ "Which list?"
      assert Grocery.list_items() == []
      assert Dictionary.category_for("quinoa") == :unknown
    end

    test "a blank entry is ignored rather than prompting", %{conn: conn} do
      view = groceries(conn)

      refute submit(view, "   ") =~ "Which list?"
      assert Grocery.list_items() == []
    end
  end

  describe "autocomplete" do
    test "offers nothing until something is typed", %{conn: conn} do
      view = groceries(conn)

      refute render(view) =~ "grocery-suggestions"
    end

    test "suggests known words as you type", %{conn: conn} do
      view = groceries(conn)

      html = type(view, "mil")

      assert html =~ "grocery-suggestions"
      assert html =~ "milk"
    end

    test "tapping a suggestion files it under that word's category", %{conn: conn} do
      view = groceries(conn)
      type(view, "brocc")

      view |> suggestion("broccoli") |> render_click()
      render(view)

      assert [%{name: "broccoli", category: "produce"}] = Grocery.list_items()
    end

    test "the suggestion list closes once something is added", %{conn: conn} do
      view = groceries(conn)
      type(view, "brocc")

      view |> suggestion("broccoli") |> render_click()

      refute render(view) =~ "grocery-suggestions"
    end
  end

  describe "forgetting a word from the suggestion list" do
    test "asks before removing anything", %{conn: conn} do
      view = groceries(conn)
      type(view, "milk")

      html = view |> forget_x("milk") |> render_click()

      assert html =~ "Forget this word?"
      # Nothing gone yet.
      assert Dictionary.category_for("milk") == {:ok, "meat_dairy"}
    end

    test "confirming removes it from the dictionary", %{conn: conn} do
      view = groceries(conn)
      type(view, "milk")
      view |> forget_x("milk") |> render_click()

      view |> element("#forget-dialog button", "Forget it") |> render_click()
      render(view)

      assert Dictionary.category_for("milk") == :unknown
    end

    test "and it stops being suggested", %{conn: conn} do
      view = groceries(conn)
      type(view, "milk")
      view |> forget_x("milk") |> render_click()
      view |> element("#forget-dialog button", "Forget it") |> render_click()

      refute settle(view) =~ ~s(phx-value-name="milk")
    end

    test "and the board asks about it again next time", %{conn: conn} do
      view = groceries(conn)
      type(view, "milk")
      view |> forget_x("milk") |> render_click()
      view |> element("#forget-dialog button", "Forget it") |> render_click()
      render(view)

      assert submit(view, "milk") =~ "Which list?"
    end

    test "cancelling keeps the word", %{conn: conn} do
      view = groceries(conn)
      type(view, "milk")
      view |> forget_x("milk") |> render_click()

      view |> element("#forget-dialog button", "Cancel") |> render_click()

      refute render(view) =~ "Forget this word?"
      assert Dictionary.category_for("milk") == {:ok, "meat_dairy"}
    end
  end

  describe "holding an item on the list" do
    test "offers to forget the word behind it", %{conn: conn} do
      view = groceries(conn)
      submit(view, "milk")

      assert hold(view, "milk") =~ "Forget this word?"
    end

    test "offers the term responsible, not the item's own name", %{conn: conn} do
      view = groceries(conn)
      submit(view, "whole milk")

      html = hold(view, "whole milk")

      assert html =~ "Forget this word?"
      # "whole milk" was never in the dictionary; "milk" is what coloured it.
      assert html =~ "milk</span>"
      refute html =~ "whole milk</span>"
    end

    test "confirming forgets it but leaves the item on the list", %{conn: conn} do
      view = groceries(conn)
      submit(view, "milk")
      hold(view, "milk")

      view |> element("#forget-dialog button", "Forget it") |> render_click()
      render(view)

      assert Dictionary.category_for("milk") == :unknown
      assert [%{name: "milk"}] = Grocery.list_items()
    end

    test "says so plainly when the word was never learned", %{conn: conn} do
      view = groceries(conn)
      {:ok, _} = Grocery.add_item("quinoa")

      html = hold(view, "quinoa")

      assert html =~ "Nothing to forget"
      refute html =~ "Forget this word?"
    end
  end
end
