defmodule TaskmasterWeb.WkukBoardTest do
  use TaskmasterWeb.ConnCase

  alias Taskmaster.Wkuk

  defp first_sketch(user) do
    Wkuk.board(user) |> Enum.find(&(&1.kind == :sketch))
  end

  describe "routing" do
    test "the landing page lists both rankers", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/wkuk")
      isolate_view(view)

      assert html =~ "greg"
      assert html =~ "john"
    end

    test "an unknown ranker is sent back to the landing page", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/wkuk"}}} = live(conn, ~p"/wkuk/nobody")
    end

    test "the board is behind the shared login" do
      conn = Phoenix.ConnTest.build_conn()
      response = get(conn, ~p"/wkuk/greg")

      assert response.status == 401
    end
  end

  describe "theme" do
    test "the wkuk pages are dark and the wall board stays light", %{conn: conn} do
      assert html_response(get(conn, ~p"/wkuk"), 200) =~ ~s(data-theme="dark")
      assert html_response(get(conn, ~p"/wkuk/greg"), 200) =~ ~s(data-theme="dark")
      assert html_response(get(conn, ~p"/"), 200) =~ ~s(data-theme="light")
    end
  end

  describe "the board" do
    test "renders every sketch, all unranked", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/wkuk/greg")
      isolate_view(view)

      assert html =~ "Unranked"
      assert html =~ "Hitler Rap"
      assert html =~ "Hitler stars in a rap video"

      counts = Wkuk.tier_counts(Wkuk.board("greg"))
      assert counts == %{"unranked" => Taskmaster.Wkuk.Catalog.count()}
      assert html =~ ~s(phx-hook="WkukDrag")
    end

    test "a drag ranks a sketch", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/wkuk/greg")
      view = isolate_view(view)

      entry = first_sketch("greg")
      render_hook(view, "move", %{"id" => entry.id, "after" => "d-S"})

      assert Wkuk.board("greg") |> Enum.find(&(&1.id == entry.id)) |> Map.fetch!(:tier) == "S"
      assert render(view) =~ "S</span>"
    end

    test "dropping on a tier letter jumps the sketch there and says where", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/wkuk/greg")
      isolate_view(view)

      entry = List.last(Enum.filter(Wkuk.board("greg"), &(&1.kind == :sketch)))

      html = render_hook(view, "move_to_tier", %{"id" => entry.id, "tier" => "A"})

      assert Wkuk.board("greg") |> Enum.find(&(&1.id == entry.id)) |> Map.fetch!(:tier) == "A"

      assert html =~
               "Moved sketch: #{Phoenix.HTML.html_escape(entry.sketch.title) |> Phoenix.HTML.safe_to_string()} to A"
    end

    test "a tier drop with junk reports rather than crashing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/wkuk/greg")
      isolate_view(view)

      html = render_hook(view, "move_to_tier", %{"id" => "d-A", "tier" => "S"})
      assert html =~ "Move rejected"

      html = render_hook(view, "move_to_tier", %{"id" => first_sketch("greg").id, "tier" => "Z"})
      assert html =~ "Move rejected"
      assert Process.alive?(view.pid)
    end

    test "the tier rail is on the page for the hook to show", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/wkuk/greg")
      isolate_view(view)

      assert html =~ ~s(id="wkuk-rail")
      assert html =~ ~s(phx-update="ignore")

      for tier <- Taskmaster.Wkuk.Divider.tiers() do
        assert html =~ ~s(data-rail-tier="#{tier}")
      end
    end

    test "a drag with a junk id reports rather than crashing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/wkuk/greg")
      view = isolate_view(view)

      html = render_hook(view, "move", %{"id" => "s-nope", "after" => nil})

      assert html =~ "Move rejected"
      assert Process.alive?(view.pid)
    end

    test "the filter hides rows but keeps every tier bar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/wkuk/greg")
      view = isolate_view(view)

      html =
        view
        |> element("form[phx-change=filter]")
        |> render_change(%{"query" => "Hitler Rap"})

      assert html =~ "Hitler Rap"
      refute html =~ "Pizza Bagels"

      for tier <- Taskmaster.Wkuk.Divider.tiers() do
        assert html =~ ~s(data-drag-id="d-#{tier}")
      end
    end
  end

  describe "the edit dialog" do
    test "saves the shared fields and the private ones", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/wkuk/greg")
      view = isolate_view(view)

      entry = first_sketch("greg")

      html = render_click(view, "edit", %{"id" => entry.id})
      assert html =~ entry.sketch.title
      assert html =~ "title is not editable"

      render_submit(view, "edit_save", %{
        "sketch" => %{
          "description" => "nazis look for jerks",
          "youtube_url" => "https://youtu.be/abc123",
          "notes" => "best one"
        }
      })

      sketch = Wkuk.get_sketch(entry.sketch.id)
      assert sketch.description == "nazis look for jerks"
      assert sketch.youtube_url == "https://youtu.be/abc123"
      assert Wkuk.notes("greg", entry.sketch.id) == "best one"
      # Shared, so john sees the description and not the notes.
      Wkuk.ensure_seeded("john")
      assert Wkuk.notes("john", entry.sketch.id) == ""
    end

    test "saves when the browser sends the hidden sketch_id back as a string", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/wkuk/greg")
      isolate_view(view)

      entry = first_sketch("greg")
      render_click(view, "edit", %{"id" => entry.id})

      # Exactly what the form posts: every control, the hidden id included.
      render_submit(view, "edit_save", %{
        "sketch" => %{
          "sketch_id" => Integer.to_string(entry.sketch.id),
          "description" => "nazis look for jerks",
          "youtube_url" => "",
          "notes" => ""
        }
      })

      assert Wkuk.get_sketch(entry.sketch.id).description == "nazis look for jerks"
      assert Process.alive?(view.pid)
    end

    test "a rejected url keeps the dialog open and names the field", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/wkuk/greg")
      view = isolate_view(view)

      entry = first_sketch("greg")
      render_click(view, "edit", %{"id" => entry.id})

      html =
        render_submit(view, "edit_save", %{
          "sketch" => %{
            "description" => "x",
            "youtube_url" => "javascript:alert(1)",
            "notes" => ""
          }
        })

      assert html =~ "Invalid field: youtube_url"
      # Still open, still carrying what was typed.
      assert html =~ "javascript:alert(1)"
      assert Wkuk.get_sketch(entry.sketch.id).youtube_url == nil
    end

    test "an unseeded sketch row is reported, not raised on", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/wkuk/greg")
      view = isolate_view(view)

      html = render_click(view, "edit", %{"id" => "s-999999"})

      assert html =~ "Unknown sketch"
      assert Process.alive?(view.pid)
    end
  end
end
