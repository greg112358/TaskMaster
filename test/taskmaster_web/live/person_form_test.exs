defmodule TaskmasterWeb.PersonFormTest do
  use TaskmasterWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Taskmaster.People

  defp open_settings(conn) do
    {:ok, view, _html} = live(conn, "/")
    view = isolate_view(view)

    view
    |> element("button[phx-value-view='settings']")
    |> render_click()

    view
  end

  defp type_name(view, name) do
    view
    |> form("#add-person-form", %{"name" => name})
    |> render_change()

    view
  end

  describe "the half-typed name" do
    test "is rendered from the server, not left in the DOM", %{conn: conn} do
      html =
        conn
        |> open_settings()
        |> type_name("Greg")
        |> render()

      assert html =~ ~s(value="Greg")
    end

    # The bug this exists to catch: with no `value` on the input the name lives
    # only in the DOM, and LiveView's next patch sets `input.value = ""` unless
    # the field happens to be focused. Removing somebody else is enough to
    # trigger it.
    test "survives an unrelated change to the list", %{conn: conn} do
      {:ok, other} = People.create_person(%{name: "Alex"})

      view = conn |> open_settings() |> type_name("Greg")

      view
      |> element("button[phx-value-id='#{other.id}']")
      |> render_click()

      html = render(view)

      refute html =~ "Alex"
      assert html =~ ~s(value="Greg")
    end

    test "is cleared once the person is added", %{conn: conn} do
      view = conn |> open_settings() |> type_name("Greg")

      view
      |> form("#add-person-form", %{"name" => "Greg"})
      |> render_submit()

      html = render(view)

      assert html =~ "Greg"
      assert html =~ ~s(value="")
    end
  end

  describe "a rejected add" do
    test "says so instead of silently doing nothing", %{conn: conn} do
      {:ok, _person} = People.create_person(%{name: "Greg"})

      view = conn |> open_settings()

      view
      |> form("#add-person-form", %{"name" => "Greg"})
      |> render_submit()

      assert render(view) =~ "Invalid field: name=&quot;Greg&quot; (has already been taken)"
      assert length(People.list_people()) == 1
    end

    test "keeps what was typed so it can be corrected", %{conn: conn} do
      {:ok, _person} = People.create_person(%{name: "Greg"})

      view = conn |> open_settings() |> type_name("Greg")

      view
      |> form("#add-person-form", %{"name" => "Greg"})
      |> render_submit()

      assert render(view) =~ ~s(value="Greg")
    end
  end
end
