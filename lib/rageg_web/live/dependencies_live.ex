defmodule RagegWeb.DependenciesLive do
  @moduledoc """
  Dependency Analysis page -- module coupling, circular deps, god modules.

  Tabs: Coupling, Circular Deps, God Modules, Unused Modules.
  Each tab lazily loads data from `Rageg.Dependencies` on first activation.
  """

  use RagegWeb, :live_view

  alias Rageg.Dependencies

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Dependencies"))
     |> assign(current_path: "/dependencies")
     |> assign(active_tab: :coupling)
     |> assign(loading: false)
     |> assign(items: [])
     |> assign(summary: nil)}
  end

  @impl Phoenix.LiveView
  def handle_params(_params, _uri, socket) do
    if connected?(socket) do
      send(self(), {:load_tab, socket.assigns.active_tab})
      {:noreply, assign(socket, loading: true)}
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)
    send(self(), {:load_tab, tab})
    {:noreply, assign(socket, active_tab: tab, loading: true, items: [])}
  end

  @impl Phoenix.LiveView
  def handle_info({:load_tab, tab}, socket) do
    items = fetch_tab_data(tab)
    summary = Dependencies.summary()

    {:noreply,
     socket
     |> assign(items: items, loading: false, summary: summary, active_tab: tab)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Header with summary --%>
      <div class="flex items-center justify-between flex-wrap gap-2">
        <div>
          <h1 class="text-2xl font-bold">{gettext("Dependencies")}</h1>
          <p class="text-sm text-base-content/60">
            {gettext("Module coupling, stability, and dependency analysis")}
          </p>
        </div>
        <div :if={@summary} class="flex gap-2 flex-wrap">
          <span class="badge badge-sm badge-ghost">
            {@summary.total_modules} {gettext("modules")}
          </span>
          <span class={[
            "badge badge-sm",
            if(@summary.circular_cycles > 0, do: "badge-error", else: "badge-ghost")
          ]}>
            {@summary.circular_cycles} {gettext("cycles")}
          </span>
          <span class={[
            "badge badge-sm",
            if(@summary.god_modules > 0, do: "badge-warning", else: "badge-ghost")
          ]}>
            {@summary.god_modules} {gettext("god modules")}
          </span>
          <span class="badge badge-sm badge-ghost">
            {@summary.unstable_modules} {gettext("unstable")}
          </span>
        </div>
      </div>

      <%!-- Tab bar --%>
      <div role="tablist" class="tabs tabs-bordered">
        <button
          :for={{tab, label, icon} <- Dependencies.tabs()}
          role="tab"
          class={["tab gap-2", if(@active_tab == tab, do: "tab-active", else: "")]}
          phx-click="switch_tab"
          phx-value-tab={tab}
        >
          <.icon name={icon} class="size-4" />
          {label}
        </button>
      </div>

      <%!-- Content --%>
      <div :if={@loading} class="flex justify-center py-12">
        <span class="loading loading-spinner loading-lg text-primary"></span>
      </div>

      <div :if={!@loading}>
        <.tab_content tab={@active_tab} items={@items} />
      </div>
    </div>
    """
  end

  # -- Tab content --

  defp tab_content(%{tab: :coupling} = assigns) do
    ~H"""
    <div :if={@items == []} class="text-center py-12 text-base-content/50">
      {gettext("No coupling data. Run an analysis first.")}
    </div>
    <div :if={@items != []} class="overflow-x-auto">
      <table class="table table-sm table-zebra">
        <thead>
          <tr>
            <th>{gettext("Module")}</th>
            <th class="text-center">{gettext("Ca (Afferent)")}</th>
            <th class="text-center">{gettext("Ce (Efferent)")}</th>
            <th class="text-center">{gettext("Total")}</th>
            <th class="text-center">{gettext("Instability")}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={entry <- @items}>
            <td class="font-mono text-xs truncate max-w-xs">{entry.module}</td>
            <td class="text-center">{entry.afferent}</td>
            <td class="text-center">{entry.efferent}</td>
            <td class="text-center font-semibold">{entry.total}</td>
            <td class="text-center">
              <span class={["badge badge-sm", instability_class(entry.instability)]}>
                {entry.instability}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
      <div class="text-xs text-base-content/50 mt-2 text-right">
        {length(@items)} {gettext("modules")}
      </div>
    </div>
    """
  end

  defp tab_content(%{tab: :circular} = assigns) do
    ~H"""
    <div :if={@items == []} class="text-center py-12 text-base-content/50">
      <.icon name="hero-check-circle" class="size-12 mx-auto mb-2 text-success/40" />
      <p>{gettext("No circular dependencies detected")}</p>
    </div>
    <div :if={@items != []} class="space-y-3">
      <div :for={{cycle, idx} <- Enum.with_index(@items, 1)} class="card bg-base-200 shadow-sm">
        <div class="card-body p-4">
          <h3 class="card-title text-sm">
            <span class="badge badge-error badge-sm">{gettext("Cycle")} {idx}</span>
            <span class="text-xs text-base-content/60">{length(cycle)} {gettext("modules")}</span>
          </h3>
          <div class="flex flex-wrap gap-1 mt-2">
            <span :for={mod <- cycle} class="badge badge-outline badge-sm font-mono">
              {mod}
            </span>
            <span class="badge badge-error badge-sm font-mono">
              {List.first(cycle)}
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp tab_content(%{tab: :god_modules} = assigns) do
    ~H"""
    <div :if={@items == []} class="text-center py-12 text-base-content/50">
      <.icon name="hero-check-circle" class="size-12 mx-auto mb-2 text-success/40" />
      <p>{gettext("No god modules detected")}</p>
    </div>
    <div :if={@items != []} class="overflow-x-auto">
      <table class="table table-sm table-zebra">
        <thead>
          <tr>
            <th>{gettext("Module")}</th>
            <th class="text-center">{gettext("Ca")}</th>
            <th class="text-center">{gettext("Ce")}</th>
            <th class="text-center">{gettext("Total Coupling")}</th>
            <th class="text-center">{gettext("Instability")}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={entry <- @items}>
            <td class="font-mono text-xs truncate max-w-xs">{entry.module}</td>
            <td class="text-center">{entry.afferent}</td>
            <td class="text-center">{entry.efferent}</td>
            <td class="text-center">
              <span class="badge badge-warning badge-sm">{entry.total}</span>
            </td>
            <td class="text-center">{entry.instability}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp tab_content(%{tab: :unused} = assigns) do
    ~H"""
    <div :if={@items == []} class="text-center py-12 text-base-content/50">
      <.icon name="hero-check-circle" class="size-12 mx-auto mb-2 text-success/40" />
      <p>{gettext("No unused modules detected")}</p>
    </div>
    <div :if={@items != []} class="space-y-1">
      <div
        :for={mod <- @items}
        class="flex items-center gap-2 p-2 rounded-box bg-base-200 text-sm font-mono"
      >
        <.icon name="hero-trash" class="size-4 text-warning" />
        {mod}
      </div>
      <div class="text-xs text-base-content/50 mt-2">
        {length(@items)} {gettext("potentially unused modules")}
      </div>
    </div>
    """
  end

  defp tab_content(assigns) do
    ~H"""
    <div class="text-center py-8 text-base-content/50">{gettext("No data available")}</div>
    """
  end

  # -- Data fetching --

  defp fetch_tab_data(:coupling) do
    {:ok, items} = Dependencies.fetch_coupling()
    items
  end

  defp fetch_tab_data(:circular) do
    {:ok, items} = Dependencies.fetch_circular_deps()
    items
  end

  defp fetch_tab_data(:god_modules) do
    {:ok, items} = Dependencies.fetch_god_modules()
    items
  end

  defp fetch_tab_data(:unused) do
    {:ok, items} = Dependencies.fetch_unused_modules()
    items
  end

  defp fetch_tab_data(_), do: []

  # -- Helpers --

  defp instability_class(i) when i >= 0.8, do: "badge-error"
  defp instability_class(i) when i >= 0.5, do: "badge-warning"
  defp instability_class(_), do: "badge-success"
end
