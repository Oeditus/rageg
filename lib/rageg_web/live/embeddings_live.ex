defmodule RagegWeb.EmbeddingsLive do
  @moduledoc """
  Embedding Space -- 2D projection of code entity embeddings.

  Features:
  - PCA-projected scatter plot of all code entity embeddings
  - Color by entity type (function/module)
  - Semantic search with result highlighting
  - Click a point to show k-NN neighbors with connecting lines
  - Stats badge (total embeddings, dimensions)
  - Zoom and pan
  """

  use RagegWeb, :live_view

  alias Rageg.Embeddings

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Embedding Space"))
     |> assign(current_path: "/embeddings")
     |> assign(search_query: "")
     |> assign(selected_point: nil)
     |> assign(neighbors: [])
     |> assign(loading: true)
     |> assign(stats: nil)
     |> assign(error: nil)}
  end

  @impl Phoenix.LiveView
  def handle_params(_params, _uri, socket) do
    if connected?(socket), do: send(self(), :load_data)
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:rageg_profile_changed, _profile}, socket) do
    send(self(), :load_data)
    {:noreply, assign(socket, loading: true, selected_point: nil, neighbors: [])}
  end

  def handle_info(:load_data, socket) do
    {:ok, points} = Embeddings.fetch_scatter_data()
    stats = Embeddings.stats()

    {:noreply,
     socket
     |> assign(loading: false, stats: stats, error: nil)
     |> push_event("scatter_data", %{points: points})}
  end

  @impl Phoenix.LiveView
  def handle_event("search", %{"query" => query}, socket) when query != "" do
    case Embeddings.search(query) do
      {:ok, ids} ->
        {:noreply,
         socket
         |> assign(search_query: query)
         |> push_event("highlight_search", %{ids: ids})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("search", _params, socket) do
    {:noreply,
     socket
     |> assign(search_query: "")
     |> push_event("clear_highlights", %{})}
  end

  def handle_event("update_search", %{"query" => query}, socket) do
    {:noreply, assign(socket, search_query: query)}
  end

  def handle_event("point_selected", %{"id" => id}, socket) do
    case Embeddings.nearest_neighbors(id, 5) do
      {:ok, neighbor_ids} ->
        {:noreply,
         socket
         |> assign(selected_point: id, neighbors: neighbor_ids)
         |> push_event("show_neighbors", %{source: id, neighbors: neighbor_ids})}

      _ ->
        {:noreply, assign(socket, selected_point: id, neighbors: [])}
    end
  end

  def handle_event("point_deselected", _params, socket) do
    {:noreply,
     socket
     |> assign(selected_point: nil, neighbors: [])
     |> push_event("clear_highlights", %{})}
  end

  def handle_event("refresh", _params, socket) do
    send(self(), :load_data)
    {:noreply, assign(socket, loading: true)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-[calc(100vh-8rem)] gap-3">
      <%!-- Controls bar --%>
      <div class="flex flex-wrap items-center gap-3">
        <h1 class="text-lg font-bold">{gettext("Embedding Space")}</h1>

        <%!-- Search --%>
        <form phx-submit="search" phx-change="update_search" class="flex gap-2">
          <input
            type="text"
            name="query"
            value={@search_query}
            placeholder={gettext("Semantic search...")}
            class="input input-sm input-bordered w-56"
          />
          <button type="submit" class="btn btn-sm btn-primary">
            <.icon name="hero-magnifying-glass" class="size-4" />
          </button>
        </form>

        <div class="flex-1"></div>

        <%!-- Stats --%>
        <div :if={@stats} class="flex gap-2 text-xs text-base-content/60">
          <span class="badge badge-ghost badge-sm">{@stats.total} {gettext("embeddings")}</span>
          <span class="badge badge-ghost badge-sm">{@stats.dimensions}d</span>
        </div>

        <%!-- Legend --%>
        <div class="flex gap-2 text-xs">
          <span class="flex items-center gap-1">
            <span class="w-3 h-3 rounded-full bg-[#4e79a7]"></span>
            {gettext("function")}
          </span>
          <span class="flex items-center gap-1">
            <span class="w-3 h-3 rounded-full bg-[#e15759]"></span>
            {gettext("module")}
          </span>
        </div>

        <button class="btn btn-sm btn-ghost" phx-click="refresh">
          <.icon name="hero-arrow-path" class="size-4" />
        </button>
      </div>

      <%!-- Main content --%>
      <div class="flex flex-1 gap-3 min-h-0">
        <%!-- Scatter plot --%>
        <div class="flex-1 relative rounded-box bg-base-200 border border-base-300 overflow-hidden">
          <div
            :if={@loading}
            class="absolute inset-0 flex items-center justify-center bg-base-200/80 z-20"
          >
            <span class="loading loading-spinner loading-lg text-primary"></span>
          </div>

          <div :if={@error} class="absolute inset-0 flex items-center justify-center z-20">
            <div class="alert alert-error max-w-md">
              <.icon name="hero-exclamation-triangle" class="size-5" />
              <span>{@error}</span>
            </div>
          </div>

          <div
            id="scatter-container"
            phx-hook="ScatterHook"
            phx-update="ignore"
            class="w-full h-full"
          >
          </div>
        </div>

        <%!-- Detail panel (when point selected) --%>
        <div
          :if={@selected_point}
          class="w-64 shrink-0 overflow-y-auto rounded-box bg-base-200 border border-base-300 p-4 space-y-3"
        >
          <div>
            <div class="text-xs text-base-content/60">{gettext("Selected")}</div>
            <h3 class="font-bold text-sm break-all font-mono">{@selected_point}</h3>
          </div>

          <div class="divider text-xs">{gettext("Nearest Neighbors")}</div>

          <div :if={@neighbors == []} class="text-xs text-base-content/50">
            {gettext("No neighbors found")}
          </div>

          <ul class="space-y-1">
            <li :for={n <- @neighbors} class="text-xs font-mono truncate text-base-content/70">
              {n}
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end
end
