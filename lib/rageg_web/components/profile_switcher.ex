defmodule RagegWeb.ProfileSwitcher do
  @moduledoc """
  LiveComponent for the profile switcher dropdown in the topbar.

  Shows the active profile name, a list of saved profiles to switch to,
  and an inline form to add a new project. Switching triggers dllb
  ingestion in a background Task with progress messages.
  """

  use RagegWeb, :live_component

  alias Rageg.Profiles

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     socket
     |> assign(profiles: Profiles.list())
     |> assign(active: Profiles.active())
     |> assign(open: false)
     |> assign(adding: false)
     |> assign(switching: false)
     |> assign(new_path: "")
     |> assign(new_name: "")
     |> assign(progress: nil)
     |> assign(error: nil)}
  end

  @impl Phoenix.LiveComponent
  def update(%{_action: :switch_progress, progress_msg: msg}, socket) do
    {:ok, assign(socket, progress: msg)}
  end

  def update(%{_action: :switch_done}, socket) do
    {:ok,
     socket
     |> assign(
       switching: false,
       progress: nil,
       active: Profiles.active(),
       profiles: Profiles.list()
     )}
  end

  def update(%{_action: :profile_switched, profile: profile}, socket) do
    {:ok, assign(socket, active: profile, profiles: Profiles.list())}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("toggle", _params, socket) do
    {:noreply, assign(socket, open: !socket.assigns.open, adding: false, error: nil)}
  end

  def handle_event("show_add", _params, socket) do
    {:noreply, assign(socket, adding: true, error: nil)}
  end

  def handle_event("cancel_add", _params, socket) do
    {:noreply, assign(socket, adding: false, new_path: "", new_name: "", error: nil)}
  end

  def handle_event("update_new", params, socket) do
    {:noreply,
     socket
     |> assign(new_path: Map.get(params, "path", socket.assigns.new_path))
     |> assign(new_name: Map.get(params, "name", socket.assigns.new_name))}
  end

  def handle_event("add_profile", %{"path" => path} = params, socket) do
    name = Map.get(params, "name", "")
    name = if name == "", do: nil, else: name

    case Profiles.create(path, name) do
      {:ok, _profile} ->
        {:noreply,
         socket
         |> assign(
           profiles: Profiles.list(),
           adding: false,
           new_path: "",
           new_name: "",
           error: nil
         )}

      {:error, reason} ->
        {:noreply, assign(socket, error: to_string(reason))}
    end
  end

  def handle_event("switch_profile", %{"id" => id}, socket) do
    parent = self()
    cid = "profile-switcher"

    Task.start(fn ->
      Profiles.switch(id,
        on_progress: fn msg ->
          Phoenix.LiveView.send_update(parent, __MODULE__,
            id: cid,
            _action: :switch_progress,
            progress_msg: msg
          )
        end
      )

      Phoenix.LiveView.send_update(parent, __MODULE__, id: cid, _action: :switch_done)
    end)

    {:noreply, assign(socket, switching: true, open: false, progress: "Switching...")}
  end

  def handle_event("delete_profile", %{"id" => id}, socket) do
    Profiles.delete(id)
    {:noreply, assign(socket, profiles: Profiles.list())}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="relative">
      <%!-- Trigger button --%>
      <button
        class={[
          "btn btn-sm gap-1 font-mono",
          if(@active, do: "btn-primary btn-soft", else: "btn-outline btn-warning")
        ]}
        phx-click="toggle"
        phx-target={@myself}
      >
        <.icon name="hero-folder" class="size-4" />
        <span class="max-w-32 truncate">
          {if @active, do: @active.name, else: gettext("No project")}
        </span>
        <.icon name="hero-chevron-down" class="size-3" />
      </button>

      <%!-- Progress indicator during switch --%>
      <div :if={@switching} class="absolute top-full right-0 mt-1 z-50 p-2 bg-base-200 rounded-box shadow-lg border border-base-300 w-64">
        <div class="flex items-center gap-2 text-xs">
          <span class="loading loading-spinner loading-xs text-primary"></span>
          <span class="truncate">{@progress}</span>
        </div>
      </div>

      <%!-- Dropdown --%>
      <div
        :if={@open and not @switching}
        class="absolute top-full right-0 mt-1 z-50 bg-base-200 rounded-box shadow-lg border border-base-300 w-72"
      >
        <%!-- Profile list --%>
        <ul class="menu menu-sm p-2">
          <li :for={profile <- @profiles}>
            <div class="flex items-center gap-2 group">
              <button
                class={["flex-1 text-left truncate", if(@active && @active.id == profile.id, do: "font-bold text-primary", else: "")]}
                phx-click="switch_profile"
                phx-value-id={profile.id}
                phx-target={@myself}
              >
                {profile.name}
              </button>
              <button
                class="btn btn-ghost btn-xs opacity-0 group-hover:opacity-100"
                phx-click="delete_profile"
                phx-value-id={profile.id}
                phx-target={@myself}
                title={gettext("Delete")}
              >
                <.icon name="hero-x-mark" class="size-3" />
              </button>
            </div>
          </li>

          <li :if={@profiles == []} class="text-xs text-base-content/50 p-2">
            {gettext("No projects yet")}
          </li>
        </ul>

        <div class="divider my-0 mx-2"></div>

        <%!-- Add project --%>
        <div :if={!@adding} class="p-2">
          <button class="btn btn-sm btn-ghost w-full gap-1" phx-click="show_add" phx-target={@myself}>
            <.icon name="hero-plus" class="size-4" />
            {gettext("Add Project")}
          </button>
        </div>

        <div :if={@adding} class="p-2 space-y-2">
          <form phx-submit="add_profile" phx-change="update_new" phx-target={@myself}>
            <input
              type="text"
              name="path"
              value={@new_path}
              placeholder="/path/to/project"
              class="input input-xs input-bordered w-full font-mono"
              required
            />
            <input
              type="text"
              name="name"
              value={@new_name}
              placeholder={gettext("Display name (optional)")}
              class="input input-xs input-bordered w-full mt-1"
            />
            <div :if={@error} class="text-xs text-error mt-1">{@error}</div>
            <div class="flex gap-1 mt-2">
              <button type="submit" class="btn btn-xs btn-primary flex-1">{gettext("Add")}</button>
              <button type="button" class="btn btn-xs btn-ghost" phx-click="cancel_add" phx-target={@myself}>
                {gettext("Cancel")}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
