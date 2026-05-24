defmodule RagegWeb.GraphLive do
  @moduledoc """
  Knowledge Graph Explorer -- interactive force-directed graph visualization.

  Fetches the code knowledge graph from Ragex, enriches it with metrics
  (PageRank, betweenness, degree, community), and renders it via a D3.js
  LiveView hook (`GraphHook`).

  ## Features

  - **Metric coloring**: toggle between PageRank, betweenness, degree, community
  - **Node sizing**: proportional to the selected metric
  - **Edge thickness**: proportional to call weight (frequency)
  - **Community hulls**: convex hull overlays when community mode is selected
  - **Minimap**: bottom-right corner overview for orientation in large graphs
  - **Filtering**: by module prefix and node type
  - **Node detail panel**: click a node to see its file, callers, callees
  - **Export**: download as SVG
  - **Max nodes slider**: control how many nodes to display (50--1000)

  ## Data Flow

  1. On mount, fetches graph data from `Rageg.Graph.fetch_d3_data/1`
  2. Pushes data to the `GraphHook` JS hook via `push_event("graph_data", ...)`
  3. User interactions in the hook push events back (`node_selected`, etc.)
  4. Detail panel is rendered server-side based on the selected node
  """

  use RagegWeb, :live_view

  alias Rageg.Graph

  @default_max_nodes 300

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Knowledge Graph"))
     |> assign(current_path: "/graph")
     |> assign(metric: "pagerank")
     |> assign(module_filter: "")
     |> assign(max_nodes: @default_max_nodes)
     |> assign(node_type_filter: "all")
     |> assign(selected_node: nil)
     |> assign(graph_stats: nil)
     |> assign(loading: true)
     |> assign(error: nil)}
  end

  @impl Phoenix.LiveView
  def handle_params(_params, _uri, socket) do
    if connected?(socket) do
      send(self(), :load_graph)
    end

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info(:load_graph, socket) do
    opts = [
      max_nodes: socket.assigns.max_nodes,
      module_filter: non_empty(socket.assigns.module_filter)
    ]

    case Graph.fetch_d3_data(opts) do
      {:ok, data} ->
        {:noreply,
         socket
         |> assign(loading: false, error: nil, graph_stats: data.stats)
         |> push_event("graph_data", data)}

      {:error, reason} ->
        {:noreply, assign(socket, loading: false, error: to_string(reason))}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("change_metric", %{"metric" => metric}, socket) do
    {:noreply,
     socket
     |> assign(metric: metric)
     |> push_event("update_metric", %{metric: metric})}
  end

  def handle_event("filter_changed", params, socket) do
    module_filter = Map.get(params, "module_filter", socket.assigns.module_filter)
    node_type = Map.get(params, "node_type", socket.assigns.node_type_filter)

    max_nodes =
      case Map.get(params, "max_nodes") do
        nil -> socket.assigns.max_nodes
        val when is_binary(val) -> String.to_integer(val)
        val -> val
      end

    socket =
      socket
      |> assign(module_filter: module_filter, node_type_filter: node_type, max_nodes: max_nodes)
      |> assign(loading: true)

    send(self(), :load_graph)
    {:noreply, socket}
  end

  def handle_event("refresh_graph", _params, socket) do
    send(self(), :load_graph)
    {:noreply, assign(socket, loading: true)}
  end

  def handle_event("export_svg", _params, socket) do
    {:noreply, push_event(socket, "export_svg", %{})}
  end

  def handle_event("export_dot", _params, socket) do
    case Graph.export_dot(max_nodes: socket.assigns.max_nodes) do
      {:ok, dot} ->
        {:noreply,
         socket
         |> push_event("download", %{
           filename: "knowledge-graph.dot",
           content: dot,
           mime: "text/vnd.graphviz"
         })}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to export DOT"))}
    end
  end

  def handle_event("node_selected", %{"node_id" => node_id}, socket) do
    details = Graph.node_details(node_id)
    {:noreply, assign(socket, selected_node: details)}
  end

  def handle_event("node_deselected", _params, socket) do
    {:noreply, assign(socket, selected_node: nil)}
  end

  def handle_event("fit_to_view", _params, socket) do
    {:noreply, push_event(socket, "fit_to_view", %{})}
  end

  # -- Render --

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-[calc(100vh-8rem)] gap-3">
      <%!-- Controls bar --%>
      <div class="flex flex-wrap items-center gap-3">
        <%!-- Metric selector --%>
        <div class="join">
          <button
            :for={{metric, label} <- Graph.available_metrics()}
            class={[
              "join-item btn btn-sm",
              if(to_string(metric) == @metric, do: "btn-primary", else: "btn-ghost")
            ]}
            phx-click="change_metric"
            phx-value-metric={metric}
          >
            {label}
          </button>
        </div>

        <div class="divider divider-horizontal mx-0"></div>

        <%!-- Module filter --%>
        <form phx-change="filter_changed" class="flex items-center gap-2">
          <.input
            type="text"
            name="module_filter"
            value={@module_filter}
            placeholder={gettext("Filter by module...")}
            class="input input-sm input-bordered w-48"
            phx-debounce="500"
          />

          <%!-- Max nodes slider --%>
          <label class="flex items-center gap-1 text-xs text-base-content/60">
            <span>{gettext("Nodes:")}</span>
            <input
              type="range"
              name="max_nodes"
              min="50"
              max="1000"
              step="50"
              value={@max_nodes}
              class="range range-xs range-primary w-24"
            />
            <span class="w-8 text-center">{@max_nodes}</span>
          </label>
        </form>

        <div class="flex-1"></div>

        <%!-- Stats badge --%>
        <div :if={@graph_stats} class="flex items-center gap-2 text-xs text-base-content/60">
          <span class="badge badge-ghost badge-sm">
            {@graph_stats.total_nodes} {gettext("nodes")}
          </span>
          <span class="badge badge-ghost badge-sm">
            {@graph_stats.total_links} {gettext("edges")}
          </span>
          <span class="badge badge-ghost badge-sm">
            {@graph_stats.community_count} {gettext("communities")}
          </span>
        </div>

        <%!-- Actions --%>
        <div class="join">
          <button
            class="join-item btn btn-sm btn-ghost"
            phx-click="refresh_graph"
            title={gettext("Refresh")}
          >
            <.icon name="hero-arrow-path" class="size-4" />
          </button>
          <button
            class="join-item btn btn-sm btn-ghost"
            phx-click="export_svg"
            title={gettext("Export SVG")}
          >
            <.icon name="hero-arrow-down-tray" class="size-4" />
          </button>
          <button
            class="join-item btn btn-sm btn-ghost"
            phx-click="export_dot"
            title={gettext("Export DOT")}
          >
            <.icon name="hero-document-text" class="size-4" />
          </button>
        </div>
      </div>

      <%!-- Main content area --%>
      <div class="flex flex-1 gap-3 min-h-0">
        <%!-- Graph container --%>
        <div class="flex-1 relative rounded-box bg-base-200 border border-base-300 overflow-hidden">
          <%!-- Loading overlay --%>
          <div
            :if={@loading}
            class="absolute inset-0 flex items-center justify-center bg-base-200/80 z-20"
          >
            <span class="loading loading-spinner loading-lg text-primary"></span>
          </div>

          <%!-- Error state --%>
          <div :if={@error} class="absolute inset-0 flex items-center justify-center z-20">
            <div class="alert alert-error max-w-md">
              <.icon name="hero-exclamation-triangle" class="size-5" />
              <span>{@error}</span>
            </div>
          </div>

          <%!-- D3 graph mount point --%>
          <div
            id="graph-container"
            phx-hook="GraphHook"
            phx-update="ignore"
            class="w-full h-full"
          >
          </div>
        </div>

        <%!-- Node detail panel --%>
        <div
          :if={@selected_node}
          class="w-80 shrink-0 overflow-y-auto rounded-box bg-base-200 border border-base-300 p-4 space-y-4"
        >
          <.node_detail_panel node={@selected_node} />
        </div>
      </div>
    </div>
    """
  end

  # -- Components --

  attr :node, :map, required: true

  defp node_detail_panel(assigns) do
    ~H"""
    <div class="space-y-3">
      <%!-- Header --%>
      <div>
        <div class="badge badge-sm badge-primary mb-1">{@node.type}</div>
        <h3 class="font-bold text-sm break-all">{@node.id}</h3>
        <p :if={@node.file} class="text-xs text-base-content/60 mt-1 break-all">
          {@node.file}{if @node.line, do: ":#{@node.line}", else: ""}
        </p>
      </div>

      <%!-- Info --%>
      <div :if={@node.module} class="text-xs">
        <span class="font-semibold">{gettext("Module:")}</span> {@node.module}
      </div>
      <div :if={@node.arity} class="text-xs">
        <span class="font-semibold">{gettext("Arity:")}</span> {@node.arity}
      </div>

      <%!-- Metrics --%>
      <div class="divider text-xs">{gettext("Connections")}</div>
      <div class="flex gap-2 text-xs">
        <div class="stat bg-base-100 rounded-box p-2 flex-1">
          <div class="stat-title text-xs">{gettext("Callers")}</div>
          <div class="stat-value text-sm">{@node.metrics.callers_count}</div>
        </div>
        <div class="stat bg-base-100 rounded-box p-2 flex-1">
          <div class="stat-title text-xs">{gettext("Callees")}</div>
          <div class="stat-value text-sm">{@node.metrics.callees_count}</div>
        </div>
      </div>

      <%!-- Callers list --%>
      <div :if={@node.callers != []} class="space-y-1">
        <h4 class="text-xs font-semibold">{gettext("Called by")}</h4>
        <ul class="text-xs space-y-0.5 max-h-32 overflow-y-auto">
          <li :for={caller <- @node.callers} class="truncate text-base-content/70">
            {caller}
          </li>
        </ul>
      </div>

      <%!-- Callees list --%>
      <div :if={@node.callees != []} class="space-y-1">
        <h4 class="text-xs font-semibold">{gettext("Calls")}</h4>
        <ul class="text-xs space-y-0.5 max-h-32 overflow-y-auto">
          <li :for={callee <- @node.callees} class="truncate text-base-content/70">
            {callee}
          </li>
        </ul>
      </div>
    </div>
    """
  end

  # -- Helpers --

  defp non_empty(""), do: nil
  defp non_empty(s) when is_binary(s), do: s
  defp non_empty(_), do: nil
end
