defmodule RagegWeb.DllbLive do
  @moduledoc """
  dllb Backend Explorer -- comprehensive visualization of dllb internals.

  Hub page with sub-views for all dllb subsystems:
  actors, storage, graph, vectors, search, code-intel.
  """

  use RagegWeb, :live_view

  alias Rageg.Dllb

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
    {:ok, assign(socket, query_input: "", query_result: nil, query_error: nil)}
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
  def handle_event("run_query", %{"query" => q}, socket) when q != "" do
    case Dllb.query(q) do
      {:ok, result} ->
        {:noreply,
         assign(socket, query_result: inspect(result, pretty: true, limit: 500), query_error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, query_error: to_string(reason), query_result: nil)}
    end
  end

  def handle_event("run_query", _params, socket), do: {:noreply, socket}

  def handle_event("update_query", %{"query" => q}, socket) do
    {:noreply, assign(socket, query_input: q)}
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

  # -- Actors sub-page --
  def render(%{action: :actors} = assigns) do
    tree = Dllb.supervision_tree()
    assigns = assign(assigns, :tree, tree)

    ~H"""
    <div class="space-y-4">
      <h1 class="text-2xl font-bold">{gettext("Supervision Tree")}</h1>
      <p class="text-sm text-base-content/60">{gettext("joerl actor supervision hierarchy")}</p>
      <.sup_node node={@tree} depth={0} />
    </div>
    """
  end

  # -- Storage sub-page --
  def render(%{action: :storage} = assigns) do
    fields = Dllb.schema_fields()
    indexes = Dllb.schema_indexes()
    assigns = assign(assigns, fields: fields, indexes: indexes)

    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">{gettext("Storage Engine")}</h1>

      <div class="card bg-base-200 shadow-sm">
        <div class="card-body p-4">
          <h2 class="card-title text-sm">{gettext("ast_node Schema")}</h2>
          <div class="overflow-x-auto">
            <table class="table table-sm table-zebra">
              <thead>
                <tr>
                  <th>{gettext("Field")}</th>
                  <th>{gettext("Type")}</th>
                  <th>{gettext("Required")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{name, type, req} <- @fields}>
                  <td class="font-mono text-xs">{name}</td>
                  <td class="text-xs">{type}</td>
                  <td><span :if={req} class="badge badge-sm badge-primary">required</span></td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div class="card bg-base-200 shadow-sm">
        <div class="card-body p-4">
          <h2 class="card-title text-sm">{gettext("Indexes")}</h2>
          <div class="overflow-x-auto">
            <table class="table table-sm table-zebra">
              <thead>
                <tr>
                  <th>{gettext("Name")}</th>
                  <th>{gettext("Fields")}</th>
                  <th>{gettext("Type")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{name, fields, type} <- @indexes}>
                  <td class="font-mono text-xs">{name}</td>
                  <td class="text-xs">{Enum.join(fields, ", ")}</td>
                  <td><span class="badge badge-sm badge-ghost">{type}</span></td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -- Graph sub-page --
  def render(%{action: :graph} = assigns) do
    edge_types = Dllb.edge_types()
    assigns = assign(assigns, :edge_types, edge_types)

    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">{gettext("Graph Model")}</h1>
      <p class="text-sm text-base-content/60">
        {gettext("Native graph edges with bidirectional traversal")}
      </p>

      <div class="card bg-base-200 shadow-sm">
        <div class="card-body p-4">
          <h2 class="card-title text-sm">{gettext("Edge Types")}</h2>
          <div class="space-y-2 mt-2">
            <div
              :for={{type, desc} <- @edge_types}
              class="flex items-center gap-3 p-2 bg-base-100 rounded-box"
            >
              <span class="badge badge-sm badge-primary font-mono">{type}</span>
              <span class="text-xs text-base-content/70">{desc}</span>
            </div>
          </div>
        </div>
      </div>

      <%!-- Query playground --%>
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body p-4">
          <h2 class="card-title text-sm">{gettext("Query Playground")}</h2>
          <form phx-submit="run_query" phx-change="update_query" class="mt-2">
            <textarea
              name="query"
              rows="3"
              class="textarea textarea-bordered w-full font-mono text-xs"
              placeholder="SELECT * FROM ast_node WHERE kind = 'function_def' LIMIT 5"
            >{@query_input}</textarea>
            <button type="submit" class="btn btn-sm btn-primary mt-2 gap-1">
              <.icon name="hero-play" class="size-4" />
              {gettext("Run")}
            </button>
          </form>
          <div :if={@query_error} class="alert alert-error mt-2 text-xs">{@query_error}</div>
          <pre
            :if={@query_result}
            class="mt-2 p-3 bg-base-100 rounded-box text-xs font-mono overflow-x-auto max-h-64"
          >{@query_result}</pre>
        </div>
      </div>
    </div>
    """
  end

  # -- Vectors sub-page --
  def render(%{action: :vectors} = assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">{gettext("HNSW Vectors")}</h1>
      <p class="text-sm text-base-content/60">
        {gettext("Approximate nearest neighbor search with HNSW index")}
      </p>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-4 text-center">
            <h3 class="text-xs font-semibold text-base-content/60">{gettext("Distance Metrics")}</h3>
            <div class="space-y-1 mt-2">
              <div
                :for={metric <- ["Cosine", "Euclidean", "Dot Product"]}
                class="badge badge-ghost badge-sm"
              >
                {metric}
              </div>
            </div>
          </div>
        </div>
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-4 text-center">
            <h3 class="text-xs font-semibold text-base-content/60">{gettext("HNSW Config")}</h3>
            <div class="text-xs mt-2 space-y-1">
              <div>M = 16, ef_construction = 200</div>
              <div>max_layers = 16</div>
            </div>
          </div>
        </div>
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-4 text-center">
            <h3 class="text-xs font-semibold text-base-content/60">{gettext("Indexes")}</h3>
            <div class="text-xs mt-2 space-y-1">
              <div>source_embedding: 768d cosine</div>
              <div>structure_embedding: 384d cosine</div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -- Search sub-page --
  def render(%{action: :search} = assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">{gettext("Full-Text Search")}</h1>
      <p class="text-sm text-base-content/60">
        {gettext("BM25-scored Tantivy indexes with code-aware tokenization")}
      </p>

      <div class="card bg-base-200 shadow-sm">
        <div class="card-body p-4">
          <h2 class="card-title text-sm">{gettext("FTS Indexes")}</h2>
          <div class="space-y-2 mt-2">
            <div class="flex items-center gap-3 p-2 bg-base-100 rounded-box">
              <span class="badge badge-sm badge-info font-mono">idx_source_text</span>
              <span class="text-xs">
                source_text field -- code-aware tokenizer (camelCase/snake_case splitting)
              </span>
            </div>
            <div class="flex items-center gap-3 p-2 bg-base-100 rounded-box">
              <span class="badge badge-sm badge-info font-mono">idx_docstring</span>
              <span class="text-xs">docstring field -- natural language tokenizer with stemming</span>
            </div>
          </div>
        </div>
      </div>

      <%!-- Query playground --%>
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body p-4">
          <h2 class="card-title text-sm">{gettext("Query Playground")}</h2>
          <form phx-submit="run_query" phx-change="update_query" class="mt-2">
            <textarea
              name="query"
              rows="3"
              class="textarea textarea-bordered w-full font-mono text-xs"
              placeholder="SELECT * FROM ast_node WHERE source_text @@ 'async trait' LIMIT 10"
            >{@query_input}</textarea>
            <button type="submit" class="btn btn-sm btn-primary mt-2 gap-1">
              <.icon name="hero-play" class="size-4" />
              {gettext("Run")}
            </button>
          </form>
          <div :if={@query_error} class="alert alert-error mt-2 text-xs">{@query_error}</div>
          <pre
            :if={@query_result}
            class="mt-2 p-3 bg-base-100 rounded-box text-xs font-mono overflow-x-auto max-h-64"
          >{@query_result}</pre>
        </div>
      </div>
    </div>
    """
  end

  # -- Code Intel sub-page --
  def render(%{action: :code_intel} = assigns) do
    node_types = Dllb.meta_ast_node_types()
    assigns = assign(assigns, :node_types, node_types)

    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">{gettext("Code Intelligence")}</h1>
      <p class="text-sm text-base-content/60">
        {gettext("MetaAST node types and code-aware analysis")}
      </p>

      <div class="card bg-base-200 shadow-sm">
        <div class="card-body p-4">
          <h2 class="card-title text-sm">
            {gettext("MetaAST Node Types")} ({length(@node_types)})
          </h2>
          <div class="flex flex-wrap gap-1.5 mt-3">
            <span
              :for={type <- @node_types}
              class="badge badge-sm badge-outline font-mono"
            >
              {type}
            </span>
          </div>
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

  # -- Supervision tree component --

  attr :node, :map, required: true
  attr :depth, :integer, required: true

  defp sup_node(assigns) do
    ~H"""
    <div class={["ml-#{@depth * 6}", if(@depth == 0, do: "", else: "border-l-2 border-base-300 pl-4")]}>
      <div class="flex items-center gap-2 p-2 rounded-box bg-base-200 my-1">
        <span class={[
          "w-2.5 h-2.5 rounded-full",
          status_color(@node[:status])
        ]}>
        </span>
        <span class="font-mono text-sm font-semibold">{@node.name}</span>
        <span :if={@node[:strategy]} class="badge badge-xs badge-ghost">{@node.strategy}</span>
        <span :if={@node[:type]} class="badge badge-xs badge-info">{@node.type}</span>
      </div>
      <div :if={@node[:children]} class="ml-4">
        <.sup_node :for={child <- @node.children} node={child} depth={@depth + 1} />
      </div>
    </div>
    """
  end

  defp status_color(:alive), do: "bg-success"
  defp status_color(:unknown), do: "bg-base-content/20"
  defp status_color(_), do: "bg-base-content/20"
end
