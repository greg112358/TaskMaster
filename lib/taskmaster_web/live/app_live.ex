defmodule TaskmasterWeb.AppLive do
  use TaskmasterWeb, :live_view

  alias Taskmaster.{Audio, People, Grocery, Events}
  alias Taskmaster.Events.Alerts
  alias Taskmaster.Grocery.Dictionary
  alias Taskmaster.Voice.Parser
  alias TaskmasterWeb.CoreComponents

  @impl true
  def mount(_params, session, socket) do
    if authorized?(session) do
      {:ok, mount_board(socket)}
    else
      # Only reachable by connecting the socket directly; a page load has
      # already been through TaskmasterWeb.Plugs.Auth.
      {:ok, redirect(socket, to: ~p"/")}
    end
  end

  defp authorized?(session) do
    case Taskmaster.Auth.fingerprint() do
      {:ok, fingerprint} -> session["auth"] == fingerprint
      :error -> false
    end
  end

  defp mount_board(socket) do
    audio? = Audio.enabled?()

    if connected?(socket) do
      People.subscribe()
      Grocery.subscribe()
      Events.subscribe()
      # Nothing fires on this topic with audio off, and nothing on the page
      # could sound it if it did.
      if audio?, do: Alerts.subscribe()
      Dictionary.subscribe()
    end

    socket
    # The microphone/speaker half of the board, off by default. Read once at
    # mount and passed down, so one session renders one way throughout.
    |> assign(:audio, audio?)
    |> assign(:current_view, :calendar)
    |> assign(:voice_status, :idle)
    |> assign(:last_voice_message, nil)
    |> assign(:device_warnings, %{})
    # The half-typed name in Settings. Held here rather than in the DOM, where
    # the next patch would wipe it.
    |> assign(:new_person_name, "")
    |> load_data()
  end

  defp load_data(socket) do
    socket
    |> assign(:people, People.list_people())
    |> assign(:grocery_items, Grocery.list_items())
    |> assign(:events, Events.list_events())
    |> assign(:tasks, Events.list_tasks())
  end

  @impl true
  def handle_event("navigate", %{"view" => view}, socket) do
    {:noreply, assign(socket, :current_view, String.to_existing_atom(view))}
  end

  def handle_event("voice_command", %{"transcript" => transcript}, socket) do
    case Parser.parse(transcript) do
      {:navigate, view} ->
        {:noreply,
         socket
         |> assign(:current_view, view)
         |> assign(:last_voice_message, "View: #{view}")}

      {:add_grocery, item_name} ->
        case Grocery.add_item(item_name) do
          {:ok, item} ->
            {:noreply, assign(socket, :last_voice_message, "Added item: #{item.name}")}

          {:error, changeset} ->
            {:noreply, assign(socket, :last_voice_message, error_message(changeset))}
        end

      :clear_groceries ->
        Grocery.clear_all()
        {:noreply, assign(socket, :last_voice_message, "Cleared groceries")}

      {:add_task, details} ->
        handle_add_task(details, socket)

      {:add_event, details} ->
        handle_add_event(details, socket)

      :unrecognized ->
        {:noreply,
         socket
         |> assign(:last_voice_message, "I missed that")
         |> speak("I missed that")}
    end
  end

  def handle_event("voice_status", %{"status" => status}, socket) do
    voice_status =
      case status do
        "listening" -> :listening
        "denied" -> :denied
        "unsupported" -> :unsupported
        _ -> :idle
      end

    {:noreply, assign(socket, :voice_status, voice_status)}
  end

  # Something the browser cannot do — no text-to-speech voices, no screen wake
  # lock. These are setup problems rather than transient ones, so they stay on
  # screen: a wall-mounted board has no keyboard to go hunting in a console
  # with. A null message clears the warning once the capability comes good.
  def handle_event("device_warning", %{"key" => key, "message" => message}, socket) do
    warnings =
      case message do
        nil -> Map.delete(socket.assigns.device_warnings, key)
        message -> Map.put(socket.assigns.device_warnings, key, message)
      end

    {:noreply, assign(socket, :device_warnings, warnings)}
  end

  # Grocery events
  def handle_event("add_grocery_item", %{"name" => name}, socket) do
    if String.trim(name) != "" do
      Grocery.add_item(String.trim(name))
    end

    {:noreply, socket}
  end

  def handle_event("toggle_grocery", %{"id" => id}, socket) do
    with_id(id, &Grocery.toggle_item/1)
    {:noreply, socket}
  end

  def handle_event("delete_grocery", %{"id" => id}, socket) do
    with_id(id, &Grocery.delete_item/1)
    {:noreply, socket}
  end

  def handle_event("clear_groceries", _params, socket) do
    Grocery.clear_all()
    {:noreply, socket}
  end

  # The long-press hook cannot address a component directly, so it comes here
  # and is handed on.
  def handle_event("hold_grocery_item", %{"name" => name}, socket) do
    send_update(TaskmasterWeb.GroceryLive, id: "grocery", confirm_forget: name)
    {:noreply, socket}
  end

  # People events
  def handle_event("person_form_changed", %{"name" => name}, socket) do
    {:noreply, assign(socket, :new_person_name, name)}
  end

  def handle_event("add_person", %{"name" => name}, socket) do
    case String.trim(name) do
      "" ->
        {:noreply, socket}

      trimmed ->
        case People.create_person(%{name: trimmed}) do
          {:ok, _person} ->
            {:noreply, assign(socket, :new_person_name, "")}

          {:error, changeset} ->
            # Keep what was typed, so the name can be corrected rather than
            # retyped.
            {:noreply, assign(socket, :last_voice_message, error_message(changeset))}
        end
    end
  end

  def handle_event("delete_person", %{"id" => id}, socket) do
    with_id(id, fn id ->
      case People.get_person(id) do
        nil -> :error
        person -> People.delete_person(person)
      end
    end)

    {:noreply, socket}
  end

  # Event/Task creation
  def handle_event("add_event", params, socket) do
    case Date.from_iso8601(to_string(params["start_date"])) do
      {:ok, start_date} ->
        attrs = %{
          title: params["title"],
          type: params["type"] || "event",
          start_date: start_date,
          person_id: parse_int(params["person_id"]),
          recurrence_type: blank_to_nil(params["recurrence_type"]),
          recurrence_interval: parse_int(params["recurrence_interval"]),
          recurrence_day_of_week: parse_int(params["recurrence_day_of_week"]),
          alert: params["alert"] == "true"
        }

        case Events.create_event(attrs) do
          {:ok, _event} ->
            {:noreply, socket}

          {:error, changeset} ->
            {:noreply, assign(socket, :last_voice_message, error_message(changeset))}
        end

      {:error, _reason} ->
        {:noreply,
         assign(
           socket,
           :last_voice_message,
           "Invalid field: start_date=#{inspect(params["start_date"])} (not a date)"
         )}
    end
  end

  def handle_event("mark_done", %{"id" => id}, socket) do
    with_id(id, &Events.mark_done/1)
    {:noreply, socket}
  end

  def handle_event("delete_event", %{"id" => id}, socket) do
    with_id(id, &Events.delete_event/1)
    {:noreply, socket}
  end

  # Calendar navigation
  def handle_event("calendar_prev", _params, socket) do
    send_update(TaskmasterWeb.CalendarLive, id: "calendar", action: :prev)
    {:noreply, socket}
  end

  def handle_event("calendar_next", _params, socket) do
    send_update(TaskmasterWeb.CalendarLive, id: "calendar", action: :next)
    {:noreply, socket}
  end

  def handle_event("calendar_toggle_view", _params, socket) do
    send_update(TaskmasterWeb.CalendarLive, id: "calendar", action: :toggle_view)
    {:noreply, socket}
  end

  # PubSub handlers
  @impl true
  def handle_info(:people_changed, socket) do
    {:noreply, assign(socket, :people, People.list_people())}
  end

  def handle_info(:groceries_changed, socket) do
    {:noreply, assign(socket, :grocery_items, Grocery.list_items())}
  end

  # The dictionary changed under the Groceries screen, so its open suggestion
  # list is now stale. Only nudge the component when it is actually mounted.
  def handle_info(:dictionary_changed, socket) do
    if socket.assigns.current_view == :groceries do
      send_update(TaskmasterWeb.GroceryLive, id: "grocery", refresh_suggestions: true)
    end

    {:noreply, socket}
  end

  def handle_info({:add_event_from_form, params}, socket) do
    handle_event("add_event", params, socket)
  end

  # Grocery writes handed up from GroceryLive.
  def handle_info({:add_grocery_item, name, category}, socket) do
    Grocery.add_item(String.trim(name), category)
    {:noreply, socket}
  end

  def handle_info({:learn_grocery_term, name, category}, socket) do
    case Dictionary.learn(name, category) do
      {:ok, term} ->
        Grocery.add_item(term.name, category)
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :last_voice_message, error_message(changeset))}
    end
  end

  def handle_info({:forget_grocery_term, name}, socket) do
    Dictionary.forget(name)
    {:noreply, assign(socket, :last_voice_message, "Deleted term: #{name}")}
  end

  def handle_info(:events_changed, socket) do
    {:noreply,
     socket
     |> assign(:events, Events.list_events())
     |> assign(:tasks, Events.list_tasks())}
  end

  # An event/task with the alert checkbox set has come due. The browser plays
  # the chime and reads the text; the banner is the visual half of the same
  # alert, for anyone who has the sound off.
  def handle_info({:alert, payload}, socket) do
    {:noreply,
     socket
     |> assign(:last_voice_message, "\u{1F514} #{payload.text}")
     |> push_event("alert", payload)}
  end

  # Speech out. With audio off there is no VoiceRecognition hook on the page to
  # receive this, so it is not pushed; the same text is already in the status
  # bar either way.
  defp speak(socket, text) do
    if socket.assigns.audio, do: push_event(socket, "speak", %{text: text}), else: socket
  end

  # Voice task handling
  defp handle_add_task(details, socket) do
    person =
      if details.person_name do
        People.find_person_by_name(details.person_name)
      end

    if details.person_name && is_nil(person) do
      {:noreply,
       socket
       |> assign(:last_voice_message, "Unknown person: #{details.person_name}")
       |> speak("Unknown person: #{details.person_name}")}
    else
      attrs = %{
        title: details.title,
        type: "task",
        start_date: Date.utc_today(),
        person_id: person && person.id,
        recurrence_type: details.recurrence_type,
        recurrence_interval: details.recurrence_interval,
        recurrence_day_of_week: details.recurrence_day_of_week
      }

      case Events.create_event(attrs) do
        {:ok, event} ->
          msg =
            if person,
              do: "Added task: #{event.title} (#{person.name})",
              else: "Added task: #{event.title}"

          {:noreply, assign(socket, :last_voice_message, msg)}

        {:error, changeset} ->
          {:noreply, assign(socket, :last_voice_message, error_message(changeset))}
      end
    end
  end

  defp handle_add_event(details, socket) do
    attrs = %{
      title: details.title,
      type: "event",
      start_date: Date.utc_today(),
      recurrence_type: details[:recurrence_type],
      recurrence_interval: details[:recurrence_interval],
      recurrence_day_of_week: details[:recurrence_day_of_week]
    }

    case Events.create_event(attrs) do
      {:ok, event} ->
        {:noreply, assign(socket, :last_voice_message, "Added event: #{event.title}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :last_voice_message, error_message(changeset))}
    end
  end

  # Ids arrive from the client in `phx-value-id`, so they can be stale — two
  # tablets share this board, and a double-tap outruns the re-render — or simply
  # not a number. None of that is worth crashing the view for: the row is already
  # gone, and whoever removed it has broadcast.
  defp with_id(id, fun) do
    case parse_int(id) do
      nil -> :error
      id -> fun.(id)
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(val) when is_integer(val), do: val

  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(val), do: val

  # The status bar is the only voice the board has, so a rejected write names the
  # field and the value that was rejected. Without this a bad save is
  # indistinguishable from one that worked and changed nothing — and "couldn't
  # save that" is no more useful than silence. Format is fixed by the `deslop`
  # skill.
  defp error_message(%Ecto.Changeset{errors: [{field, error} | _]} = changeset) do
    case CoreComponents.translate_error(error) do
      "can't be blank" ->
        "Missing field: #{field}"

      constraint ->
        "Invalid field: #{field}=#{inspect(rejected_value(changeset, field))} (#{constraint})"
    end
  end

  defp error_message(%Ecto.Changeset{}), do: "Write rejected"

  # What was typed, not what it cast to — a value that failed to cast has no
  # entry in `changes` at all.
  defp rejected_value(changeset, field) do
    case Map.fetch(changeset.params || %{}, to_string(field)) do
      {:ok, value} -> value
      :error -> Ecto.Changeset.get_field(changeset, field)
    end
  end

  defp voice_hints(:calendar) do
    [
      ~s(\"add task for Greg clean cat tree every 2 weeks\"),
      ~s(\"add event Birthday every year\"),
      ~s(\"show groceries\")
    ]
  end

  defp voice_hints(:groceries) do
    [
      ~s(\"add milk to groceries\"),
      ~s(\"clear groceries\"),
      ~s(\"show calendar\")
    ]
  end

  defp voice_hints(:chores) do
    [
      ~s(\"add task vacuum every week\"),
      ~s(\"show calendar\"),
      ~s(\"show groceries\")
    ]
  end

  defp voice_hints(:settings) do
    [~s(\"show calendar\"), ~s(\"show groceries\")]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- No phx-hook with audio off: the hook is what constructs the
          SpeechRecognition, the AudioContext and the speech synthesiser, so
          leaving it off is what keeps the board silent and never asks for the
          microphone. --%>
    <div
      id="app-root"
      phx-hook={if @audio, do: "VoiceRecognition"}
      class="flex flex-col h-screen"
    >
      <%!-- Keeps the screen awake. Its own element because an element carries
            only one phx-hook. --%>
      <div id="wake-lock" phx-hook="WakeLock" class="hidden"></div>

      <%!-- Status bar. The voice half of it only when audio is on; device
            warnings and write errors are shown either way. --%>
      <div class={[
        "bg-base-200 px-4 py-2 flex items-center text-sm",
        if(@audio, do: "justify-between", else: "justify-end")
      ]}>
        <div :if={@audio} class="flex items-center gap-2">
          <span class={"inline-block w-3 h-3 rounded-full #{if @voice_status == :listening, do: "bg-success animate-pulse", else: "bg-error"}"}>
          </span>
          <span class="text-base-content/60">
            Try saying:
            <span :for={hint <- voice_hints(@current_view)} class="mx-1 text-base-content/80">
              {hint}
            </span>
          </span>
        </div>
        <div class="flex items-center gap-4">
          <div
            :for={{key, message} <- Enum.sort(@device_warnings)}
            id={"warning-#{key}"}
            class="text-warning font-medium"
          >
            &#9888; {message}
          </div>
          <div :if={@last_voice_message} class="text-primary font-medium">
            {@last_voice_message}
          </div>
        </div>
      </div>

      <%!-- Main content --%>
      <main class="flex-1 overflow-y-auto p-4">
        <div :if={@current_view == :calendar}>
          <.live_component
            module={TaskmasterWeb.CalendarLive}
            id="calendar"
            events={@events}
            people={@people}
            audio={@audio}
          />
        </div>
        <div :if={@current_view == :groceries}>
          <.live_component
            module={TaskmasterWeb.GroceryLive}
            id="grocery"
            items={@grocery_items}
          />
        </div>
        <div :if={@current_view == :chores}>
          <.live_component
            module={TaskmasterWeb.ChoreListLive}
            id="chores"
            tasks={@tasks}
            audio={@audio}
          />
        </div>
        <div :if={@current_view == :settings}>
          <.live_component
            module={TaskmasterWeb.SettingsLive}
            id="settings"
            people={@people}
            new_person_name={@new_person_name}
          />
        </div>
      </main>

      <%!-- Bottom navigation --%>
      <nav class="flex border-t-2 border-base-300 bg-base-100">
        <button
          :for={
            {view, label} <- [
              calendar: "Calendar",
              groceries: "Groceries",
              chores: "Chores",
              settings: "Settings"
            ]
          }
          phx-click="navigate"
          phx-value-view={view}
          class={"flex-1 py-5 text-2xl font-bold text-center transition-colors cursor-pointer
            #{if @current_view == view, do: "bg-primary text-primary-content", else: "hover:bg-base-200"}"}
        >
          {label}
        </button>
      </nav>
    </div>
    """
  end
end
