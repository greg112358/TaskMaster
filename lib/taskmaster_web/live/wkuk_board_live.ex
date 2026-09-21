defmodule TaskmasterWeb.WkukBoardLive do
  @moduledoc """
  One person's sketch ranking board, at `/wkuk/:user`.

  A second front end on the same release, and deliberately not part of the wall
  board: `TaskmasterWeb.AppLive` owns the appliance screens and this owns
  `/wkuk`. They share the login and nothing else.

  ## Sizing is not the wall board's sizing

  CLAUDE.md's "readable from ten feet, no small text" rule is a constraint on the
  appliance. This screen is a phone-and-desktop app holding four hundred rows, so
  it uses ordinary type with touch-sized hit targets (the drag handle is 48px)
  rather than `text-xl` everywhere. Do not "fix" it to match the board.

  ## State

  `@entries` is the *visible* list — `@query` filters it — and `@counts` is
  computed from the unfiltered board so the tier totals in the header do not
  move when somebody searches. Dividers are never filtered out: they are the
  drop targets that make a filtered list still rankable.

  The edit dialog's fields live in `@editing`, not in the DOM. A LiveView patch
  overwrites an input the server renders without a value (`bug-patterns` P1),
  and a reorder by the other tablet patches this page mid-edit.
  """

  use TaskmasterWeb, :live_view

  alias Taskmaster.Wkuk
  alias TaskmasterWeb.ErrorMessage

  @impl true
  def mount(%{"user" => user}, session, socket) do
    cond do
      not authorized?(session) ->
        # Only reachable by connecting the socket directly; a page load has
        # already been through TaskmasterWeb.Plugs.Auth.
        {:ok, redirect(socket, to: ~p"/wkuk")}

      not Wkuk.user?(user) ->
        {:ok, redirect(socket, to: ~p"/wkuk")}

      true ->
        Wkuk.ensure_seeded(user)
        if connected?(socket), do: Wkuk.subscribe(user)

        {:ok,
         socket
         |> assign(:page_title, "WKUK — " <> user)
         |> assign(:user, user)
         |> assign(:query, "")
         |> assign(:editing, nil)
         |> assign(:status, nil)
         |> load_board()}
    end
  end

  defp authorized?(session) do
    case Taskmaster.Auth.fingerprint() do
      {:ok, fingerprint} -> session["auth"] == fingerprint
      :error -> false
    end
  end

  defp load_board(socket) do
    entries = Wkuk.board(socket.assigns.user)

    socket
    |> assign(:counts, Wkuk.tier_counts(entries))
    |> assign(:entries, filter(entries, socket.assigns.query))
  end

  # Dividers always survive the filter. Drop them and a filtered list has no
  # drop targets, so a search would make the board unrankable.
  defp filter(entries, ""), do: entries

  defp filter(entries, query) do
    needle = String.downcase(query)

    Enum.filter(entries, fn
      %{kind: :divider} -> true
      %{kind: :sketch} = entry -> matches?(entry, needle)
    end)
  end

  defp matches?(entry, needle) do
    haystack =
      [
        entry.sketch.title,
        entry.sketch.description,
        entry.notes,
        "s#{entry.sketch.season}e#{entry.sketch.episode}"
      ]
      |> Enum.join(" ")
      |> String.downcase()

    String.contains?(haystack, needle)
  end

  # --------------------------------------------------------------- events --

  @impl true
  def handle_event("filter", %{"query" => query}, socket) do
    {:noreply, socket |> assign(:query, query) |> load_board()}
  end

  # Pushed by the WkukDrag hook on release. `after` is the id of the row the
  # dragged one should land below, or nil for the top of the list. Both are
  # client input, so every failure answers with a status line rather than
  # raising — see bug-patterns P4.
  def handle_event("move", %{"id" => id} = params, socket) do
    case Wkuk.move(socket.assigns.user, id, params["after"]) do
      :ok ->
        # The write broadcasts; the reload happens in handle_info. Recomputing
        # here would race it (bug-patterns P6).
        {:noreply, assign(socket, :status, nil)}

      :error ->
        {:noreply, assign(socket, :status, "Move rejected: id=#{inspect(id)}")}
    end
  end

  # A sketch dropped on a tier letter in the rail the hook shows mid-drag. The
  # status names the tier, because the row has just left the part of the list on
  # screen and nothing else says where it went.
  def handle_event("move_to_tier", %{"id" => id, "tier" => tier}, socket) do
    case Wkuk.move_to_tier(socket.assigns.user, id, tier) do
      :ok ->
        {:noreply, assign(socket, :status, moved_message(id, tier))}

      :error ->
        {:noreply,
         assign(socket, :status, "Move rejected: id=#{inspect(id)} tier=#{inspect(tier)}")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    with {:ok, {:sketch, sketch_id}} <- Wkuk.decode_id(id),
         sketch when not is_nil(sketch) <- Wkuk.get_sketch(sketch_id) do
      {:noreply,
       assign(socket, :editing, %{
         "sketch_id" => sketch_id,
         "title" => sketch.title,
         "description" => sketch.description || "",
         "youtube_url" => sketch.youtube_url || "",
         "notes" => Wkuk.notes(socket.assigns.user, sketch_id)
       })}
    else
      _ -> {:noreply, assign(socket, :status, "Unknown sketch: #{inspect(id)}")}
    end
  end

  def handle_event("edit_cancel", _params, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  # Every keystroke, so the dialog's values live in the assign rather than only
  # in the DOM. phx-change is on the form, not on one control (P1).
  def handle_event("edit_change", _params, %{assigns: %{editing: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("edit_change", %{"sketch" => params}, socket) do
    {:noreply, assign(socket, :editing, merge_fields(socket.assigns.editing, params))}
  end

  # The dialog was closed under this event, by the other tablet's reload or a
  # double-tap on Save. Nothing left to save.
  def handle_event("edit_save", _params, %{assigns: %{editing: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("edit_save", %{"sketch" => params}, socket) do
    editing = merge_fields(socket.assigns.editing, params)
    sketch_id = editing["sketch_id"]

    shared = %{
      description: editing["description"],
      youtube_url: editing["youtube_url"]
    }

    with {:ok, sketch} <- Wkuk.update_sketch(sketch_id, shared),
         {:ok, _ranking} <- Wkuk.update_notes(socket.assigns.user, sketch_id, editing["notes"]) do
      {:noreply,
       socket
       |> assign(:editing, nil)
       |> assign(:status, "Saved sketch: #{sketch.title}")}
    else
      {:error, changeset} ->
        # The dialog stays open carrying what was typed, so the rejected value
        # is still there to fix.
        {:noreply,
         socket |> assign(:editing, editing) |> assign(:status, ErrorMessage.build(changeset))}

      :error ->
        {:noreply,
         socket
         |> assign(:editing, nil)
         |> assign(:status, "Unknown sketch: #{inspect(sketch_id)}")}
    end
  end

  # `sketch_id` and `title` are the server's, set once by "edit". Merging the
  # whole form over them let the browser's copy of the id, a string, replace the
  # integer and crash the save. Only the three editable fields come from the form.
  @editable ~w(description youtube_url notes)

  defp merge_fields(editing, params) do
    Map.merge(editing, Map.take(params, @editable))
  end

  defp moved_message(id, tier) do
    title =
      with {:ok, {:sketch, sketch_id}} <- Wkuk.decode_id(id),
           %{title: title} <- Wkuk.get_sketch(sketch_id) do
        title
      else
        _ -> id
      end

    "Moved sketch: #{title} to #{tier_label(tier)}"
  end

  @impl true
  def handle_info(:wkuk_board_changed, socket), do: {:noreply, load_board(socket)}
  def handle_info(:wkuk_sketches_changed, socket), do: {:noreply, load_board(socket)}

  # ---------------------------------------------------------------- render --

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <header class="sticky top-0 z-30 border-b border-base-300 bg-base-100">
        <div class="flex flex-wrap items-center gap-3 px-3 py-2">
          <.link navigate={~p"/wkuk"} class="text-lg font-bold tracking-tight">WKUK</.link>

          <div class="join">
            <.link
              :for={user <- Wkuk.users()}
              navigate={~p"/wkuk/#{user}"}
              class={[
                "join-item btn btn-sm",
                user == @user && "btn-primary"
              ]}
            >
              {user}
            </.link>
          </div>

          <form phx-change="filter" phx-submit="filter" class="grow min-w-40">
            <input
              type="search"
              name="query"
              value={@query}
              placeholder="Filter"
              phx-debounce="200"
              autocomplete="off"
              class="input input-sm input-bordered w-full"
            />
          </form>
        </div>

        <div class="flex gap-1 overflow-x-auto px-3 pb-2">
          <span
            :for={tier <- Taskmaster.Wkuk.Divider.tiers()}
            class={["rounded px-2 py-0.5 text-xs font-bold whitespace-nowrap", tier_class(tier)]}
          >
            {tier_label(tier)} {Map.get(@counts, tier, 0)}
          </span>
        </div>

        <p :if={@status} class="border-t border-base-300 px-3 py-1 font-mono text-xs">
          {@status}
        </p>
      </header>

      <ol
        id="wkuk-list"
        phx-hook="WkukDrag"
        class="select-none px-2 pt-2 pb-32"
      >
        <li
          :for={entry <- @entries}
          id={"row-" <> entry.id}
          data-drag-id={entry.id}
          class="mb-1"
        >
          <.divider_row :if={entry.kind == :divider} entry={entry} counts={@counts} />
          <.sketch_row :if={entry.kind == :sketch} entry={entry} />
        </li>
        <li :if={@entries == []} class="p-4 font-mono text-sm">None</li>
      </ol>

      <%!-- Shown by the drag hook while a sketch is held. phx-update="ignore" so a
           patch does not undo its display toggle; it is static, so nothing is lost. --%>
      <div
        id="wkuk-rail"
        phx-update="ignore"
        style="display: none"
        class="fixed top-2 right-2 bottom-2 z-[70] w-16 flex-col gap-1"
      >
        <div
          :for={tier <- Taskmaster.Wkuk.Divider.tiers()}
          data-rail-tier={tier}
          class={
            [
              "flex min-h-0 flex-1 items-center justify-center rounded-lg text-2xl font-black shadow-lg ring-inset",
              tier_class(tier),
              # Grey on the dark page is close to invisible without an edge.
              tier == "unranked" && "border-2 border-base-content/40"
            ]
          }
        >
          <span class={tier == "unranked" && "text-[10px] font-bold"}>{tier_label(tier)}</span>
        </div>
      </div>

      <.edit_dialog :if={@editing} editing={@editing} />
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :counts, :map, required: true

  defp divider_row(assigns) do
    ~H"""
    <div class={[
      "flex items-stretch overflow-hidden rounded-lg shadow-sm",
      tier_class(@entry.tier)
    ]}>
      <div
        :if={@entry.draggable?}
        data-drag-handle
        title="Drag to resize this tier"
        class="flex w-12 shrink-0 cursor-grab touch-none items-center justify-center text-2xl opacity-70"
      >
        ⠿
      </div>
      <div :if={not @entry.draggable?} class="w-12 shrink-0" aria-hidden="true"></div>

      <div class="flex grow items-center gap-3 py-3 pr-3">
        <span class="text-2xl leading-none font-black">{tier_label(@entry.tier)}</span>
        <span class="font-mono text-xs opacity-80">{Map.get(@counts, @entry.tier, 0)}</span>
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true

  defp sketch_row(assigns) do
    ~H"""
    <div class="flex items-stretch overflow-hidden rounded-lg border border-base-300 bg-base-100">
      <div
        data-drag-handle
        title="Drag to rank"
        class="flex w-12 shrink-0 cursor-grab touch-none items-center justify-center text-xl text-base-content/40"
      >
        ⠿
      </div>

      <div class="min-w-0 grow py-2 pr-1">
        <div class="flex items-baseline gap-2">
          <span class={[
            "rounded px-1.5 text-xs font-bold",
            tier_class(@entry.tier)
          ]}>
            {tier_label(@entry.tier)}
          </span>
          <span class="truncate font-semibold">{@entry.sketch.title}</span>
        </div>
        <div class="flex items-baseline gap-2 text-sm text-base-content/70">
          <span class="font-mono text-xs whitespace-nowrap">
            S{@entry.sketch.season}E{@entry.sketch.episode}
          </span>
          <span class="truncate">{@entry.sketch.description}</span>
        </div>
      </div>

      <a
        href={watch_url(@entry.sketch)}
        target="_blank"
        rel="noopener"
        title={if @entry.sketch.youtube_url, do: "Watch", else: "Search YouTube"}
        class={[
          "flex w-12 shrink-0 items-center justify-center text-xl",
          @entry.sketch.youtube_url || "opacity-30"
        ]}
      >
        ▶
      </a>

      <button
        type="button"
        phx-click="edit"
        phx-value-id={@entry.id}
        title="Edit"
        class="flex w-12 shrink-0 items-center justify-center text-lg"
      >
        <span class={[@entry.notes != "" && "text-primary"]}>✎</span>
      </button>
    </div>
    """
  end

  attr :editing, :map, required: true

  defp edit_dialog(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-end justify-center bg-black/50 sm:items-center">
      <div class="max-h-[90vh] w-full overflow-y-auto rounded-t-2xl bg-base-100 p-4 sm:max-w-lg sm:rounded-2xl">
        <h2 class="mb-1 text-lg font-bold">{@editing["title"]}</h2>
        <p class="mb-3 font-mono text-xs text-base-content/60">title is not editable</p>

        <form phx-change="edit_change" phx-submit="edit_save" class="flex flex-col gap-3">
          <label class="flex flex-col gap-1">
            <span class="font-mono text-xs">description — shared</span>
            <textarea
              name="sketch[description]"
              rows="2"
              maxlength="200"
              class="textarea textarea-bordered w-full"
            >{@editing["description"]}</textarea>
          </label>

          <label class="flex flex-col gap-1">
            <span class="font-mono text-xs">youtube_url — shared</span>
            <input
              type="url"
              name="sketch[youtube_url]"
              value={@editing["youtube_url"]}
              placeholder="https://youtube.com/watch?v="
              inputmode="url"
              autocomplete="off"
              class="input input-bordered w-full"
            />
          </label>

          <label class="flex flex-col gap-1">
            <span class="font-mono text-xs">notes — yours only</span>
            <textarea name="sketch[notes]" rows="4" class="textarea textarea-bordered w-full">{@editing["notes"]}</textarea>
          </label>

          <div class="flex gap-2">
            <button type="submit" class="btn btn-primary grow">Save</button>
            <button type="button" phx-click="edit_cancel" class="btn grow">Cancel</button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  # A seeded link when somebody has pasted one, a YouTube search for the title
  # when nobody has. Guessing a video id would put wrong links on 384 rows.
  defp watch_url(%{youtube_url: url}) when is_binary(url), do: url

  defp watch_url(sketch) do
    "https://www.youtube.com/results?" <>
      URI.encode_query(%{"search_query" => "WKUK " <> sketch.title})
  end

  defp tier_label("unranked"), do: "Unranked"
  defp tier_label(tier), do: tier

  # Static strings so the Tailwind scanner finds them. The catch-all is
  # bug-patterns P3: `tier` is a string column and this drives a lookup.
  defp tier_class("S"), do: "bg-rose-500 text-white"
  defp tier_class("A"), do: "bg-orange-500 text-white"
  defp tier_class("B"), do: "bg-amber-400 text-black"
  defp tier_class("C"), do: "bg-yellow-300 text-black"
  defp tier_class("D"), do: "bg-lime-400 text-black"
  defp tier_class("E"), do: "bg-emerald-400 text-black"
  defp tier_class("F"), do: "bg-sky-400 text-black"
  defp tier_class(_), do: "bg-base-300 text-base-content"
end
