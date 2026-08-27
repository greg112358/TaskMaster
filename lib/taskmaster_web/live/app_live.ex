defmodule TaskmasterWeb.AppLive do
  use TaskmasterWeb, :live_view

  alias Taskmaster.{People, Grocery, Events}
  alias Taskmaster.Events.Alerts
  alias Taskmaster.Voice.Parser

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      People.subscribe()
      Grocery.subscribe()
      Events.subscribe()
      Alerts.subscribe()
    end

    {:ok,
     socket
     |> assign(:current_view, :calendar)
     |> assign(:voice_status, :idle)
     |> assign(:last_voice_message, nil)
     |> assign(:speech_error, nil)
     |> load_data()}
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
         |> assign(:last_voice_message, "Showing #{view}")}

      {:add_grocery, item_name} ->
        case Grocery.add_item(item_name) do
          {:ok, _item} ->
            {:noreply, assign(socket, :last_voice_message, "Added #{item_name}")}

          _ ->
            {:noreply, assign(socket, :last_voice_message, "Couldn't add #{item_name}")}
        end

      :clear_groceries ->
        Grocery.clear_all()
        {:noreply, assign(socket, :last_voice_message, "Groceries cleared")}

      {:add_task, details} ->
        handle_add_task(details, socket)

      {:add_event, details} ->
        handle_add_event(details, socket)

      :unrecognized ->
        {:noreply,
         socket
         |> assign(:last_voice_message, "I missed that")
         |> push_event("speak", %{text: "I missed that"})}
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

  # The browser could not read an alert out. This is a setup problem rather
  # than a transient one, so it stays on screen: the board has no keyboard to
  # go looking in a console with.
  def handle_event("speech_unavailable", %{"reason" => reason}, socket) do
    {:noreply, assign(socket, :speech_error, "Can't read alerts aloud: #{reason}")}
  end

  # Grocery events
  def handle_event("add_grocery_item", %{"name" => name}, socket) do
    if String.trim(name) != "" do
      Grocery.add_item(String.trim(name))
    end

    {:noreply, socket}
  end

  def handle_event("toggle_grocery", %{"id" => id}, socket) do
    Grocery.toggle_item(String.to_integer(id))
    {:noreply, socket}
  end

  def handle_event("delete_grocery", %{"id" => id}, socket) do
    Grocery.delete_item(String.to_integer(id))
    {:noreply, socket}
  end

  def handle_event("clear_groceries", _params, socket) do
    Grocery.clear_all()
    {:noreply, socket}
  end

  # People events
  def handle_event("add_person", %{"name" => name}, socket) do
    if String.trim(name) != "" do
      People.create_person(%{name: String.trim(name)})
    end

    {:noreply, socket}
  end

  def handle_event("delete_person", %{"id" => id}, socket) do
    person = People.get_person!(String.to_integer(id))
    People.delete_person(person)
    {:noreply, socket}
  end

  # Event/Task creation
  def handle_event("add_event", params, socket) do
    attrs = %{
      title: params["title"],
      type: params["type"] || "event",
      start_date: Date.from_iso8601!(params["start_date"]),
      person_id: parse_person_id(params["person_id"]),
      recurrence_type: blank_to_nil(params["recurrence_type"]),
      recurrence_interval: parse_int(params["recurrence_interval"]),
      recurrence_day_of_week: parse_int(params["recurrence_day_of_week"]),
      alert: params["alert"] == "true"
    }

    Events.create_event(attrs)
    {:noreply, socket}
  end

  def handle_event("mark_done", %{"id" => id}, socket) do
    Events.mark_done(String.to_integer(id))
    {:noreply, socket}
  end

  def handle_event("delete_event", %{"id" => id}, socket) do
    Events.delete_event(String.to_integer(id))
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

  def handle_info({:add_event_from_form, params}, socket) do
    handle_event("add_event", params, socket)
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

  # Voice task handling
  defp handle_add_task(details, socket) do
    person =
      if details.person_name do
        People.find_person_by_name(details.person_name)
      end

    if details.person_name && is_nil(person) do
      {:noreply,
       socket
       |> assign(:last_voice_message, "I don't know #{details.person_name}")
       |> push_event("speak", %{text: "I don't know #{details.person_name}"})}
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
        {:ok, _} ->
          msg =
            if person,
              do: "Added task #{details.title} for #{person.name}",
              else: "Added task #{details.title}"

          {:noreply, assign(socket, :last_voice_message, msg)}

        _ ->
          {:noreply, assign(socket, :last_voice_message, "Couldn't add that task")}
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
      {:ok, _} ->
        {:noreply, assign(socket, :last_voice_message, "Added event #{details.title}")}

      _ ->
        {:noreply, assign(socket, :last_voice_message, "Couldn't add that event")}
    end
  end

  defp parse_person_id(""), do: nil
  defp parse_person_id(nil), do: nil
  defp parse_person_id(id), do: String.to_integer(id)

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(val) when is_binary(val), do: String.to_integer(val)
  defp parse_int(val) when is_integer(val), do: val

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(val), do: val

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
    <div id="app-root" phx-hook="VoiceRecognition" class="flex flex-col h-screen">
      <%!-- Voice hint bar --%>
      <div class="bg-base-200 px-4 py-2 flex items-center justify-between text-sm">
        <div class="flex items-center gap-2">
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
          <div :if={@speech_error} class="text-warning font-medium">
            {@speech_error}
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
          />
        </div>
        <div :if={@current_view == :settings}>
          <.live_component
            module={TaskmasterWeb.SettingsLive}
            id="settings"
            people={@people}
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
