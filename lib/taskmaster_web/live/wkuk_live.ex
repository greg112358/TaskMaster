defmodule TaskmasterWeb.WkukLive do
  @moduledoc """
  The `/wkuk` landing: pick whose rankings to open.

  Two boards, one login. The path segment is the whole of the identity — these
  are two ranking profiles on a family device, not two accounts.
  """

  use TaskmasterWeb, :live_view

  alias Taskmaster.Wkuk

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "WKUK")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex min-h-screen flex-col items-center justify-center gap-6 bg-base-200 p-6">
      <h1 class="text-3xl font-black tracking-tight">WKUK</h1>
      <p class="font-mono text-sm text-base-content/70">
        {Taskmaster.Wkuk.Catalog.count()} sketches
      </p>

      <div class="flex w-full max-w-sm flex-col gap-3">
        <.link
          :for={user <- Wkuk.users()}
          navigate={~p"/wkuk/#{user}"}
          class="btn btn-lg btn-primary"
        >
          {user}
        </.link>
      </div>
    </div>
    """
  end
end
