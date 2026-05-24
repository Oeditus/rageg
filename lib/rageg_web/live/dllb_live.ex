defmodule RagegWeb.DllbLive do
  @moduledoc """
  dllb Backend Explorer -- Phase 7.

  Hub page for exploring the dllb multi-model database internals.
  Routes to sub-views via the `:live_action` assign:

  - `:index`      -- overview of all dllb subsystems
  - `:actors`     -- joerl supervision tree
  - `:storage`    -- keyspace browser and write throughput
  - `:graph`      -- edge browser and traversal playground
  - `:vectors`    -- HNSW layer visualization
  - `:search`     -- Tantivy full-text search playground
  - `:code_intel` -- MetaAST tree viewer
  """

  use RagegWeb, :live_view

  @sub_pages %{
    index: %{title: "dllb Overview", icon: "hero-circle-stack", path: "/dllb"},
    actors: %{title: "Supervision Tree", icon: "hero-cpu-chip", path: "/dllb/actors"},
    storage: %{title: "Storage Engine", icon: "hero-server-stack", path: "/dllb/storage"},
    graph: %{title: "Graph Model", icon: "hero-share", path: "/dllb/graph"},
    vectors: %{title: "HNSW Vectors", icon: "hero-cube", path: "/dllb/vectors"},
    search: %{title: "Full-Text Search", icon: "hero-magnifying-glass", path: "/dllb/search"},
    code_intel: %{title: "Code Intelligence", icon: "hero-code-bracket", path: "/dllb/code-intel"}
  }

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(_params, uri, socket) do
    action = socket.assigns.live_action || :index
    page = Map.get(@sub_pages, action, @sub_pages.index)

    {:noreply,
     socket
     |> assign(page_title: page.title)
     |> assign(current_path: URI.parse(uri).path || page.path)
     |> assign(action: action)
     |> assign(page: page)}
  end

  @impl Phoenix.LiveView
  def render(%{action: :index} = assigns) do
    sub_pages =
      @sub_pages
      |> Enum.reject(fn {k, _} -> k == :index end)
      |> Enum.sort_by(fn {k, _} -> k end)

    assigns = assign(assigns, :sub_pages, sub_pages)

    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold">{gettext("dllb Backend Explorer")}</h1>
        <p class="text-sm text-base-content/60">
          {gettext("Multi-model NoSQL database: documents, graphs, full-text, vectors")}
        </p>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <.dllb_card
          :for={{key, sub} <- @sub_pages}
          title={sub.title}
          icon={sub.icon}
          path={sub.path}
          description={dllb_description(key)}
        />
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="hero min-h-[60vh]">
      <div class="hero-content text-center">
        <div class="max-w-md">
          <.icon name={@page.icon} class="size-16 text-primary mx-auto mb-4" />
          <h1 class="text-3xl font-bold">{@page.title}</h1>
          <p class="py-4 text-base-content/70">{dllb_description(@action)}</p>
          <div class="badge badge-outline">Phase 7</div>
        </div>
      </div>
    </div>
    """
  end

  # -- Components --

  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :path, :string, required: true
  attr :description, :string, required: true

  defp dllb_card(assigns) do
    ~H"""
    <.link
      navigate={@path}
      class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow cursor-pointer"
    >
      <div class="card-body p-4">
        <h3 class="card-title text-sm">
          <.icon name={@icon} class="size-5 text-primary" />
          {@title}
        </h3>
        <p class="text-xs text-base-content/60">{@description}</p>
      </div>
    </.link>
    """
  end

  defp dllb_description(:actors),
    do: "Live joerl supervision tree with actor health and mailbox depth"

  defp dllb_description(:storage),
    do: "Keyspace browser, key distribution, write throughput and read latency"

  defp dllb_description(:graph),
    do: "Edge browser, traversal playground, and edge type distribution"

  defp dllb_description(:vectors),
    do: "HNSW layer visualization, search replay, and recall dashboard"

  defp dllb_description(:search),
    do: "Tantivy index browser, BM25 query playground, token analyzer"

  defp dllb_description(:code_intel),
    do: "MetaAST tree viewer with 38 node types and cross-language map"

  defp dllb_description(_), do: ""
end
