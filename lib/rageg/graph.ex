defmodule Rageg.Graph do
  @moduledoc """
  Context module for knowledge graph data.

  Wraps `Ragex.Graph.Algorithms` and `Ragex.Graph.Store` to provide
  graph data in the shape the LiveView and D3.js hook expect.

  ## Data Flow

      GraphLive mount -> Rageg.Graph.fetch_d3_data/1 -> push_event to JS hook
      JS hook click   -> pushEvent("node_selected") -> Rageg.Graph.node_details/1

  ## Node ID Format

  Ragex stores node IDs as tuples (e.g. `{:function, Module, :name, 2}`).
  The D3 export serializes them as strings like `"Module.name/2"`. This
  module handles both representations.
  """

  alias Ragex.Graph.{Algorithms, Store}

  @type metric :: :pagerank | :betweenness | :closeness | :degree | :community
  @type layout :: :force | :hierarchical | :circular

  @type d3_data :: %{
          nodes: [map()],
          links: [map()],
          communities: map(),
          stats: map()
        }

  @doc """
  Fetches the full graph in D3.js format with enriched metadata.

  Returns nodes with all metrics pre-computed so the JS hook can
  switch coloring modes without a server round-trip.

  ## Options

    * `:max_nodes` - max nodes to include (default: 500)
    * `:include_communities` - detect communities (default: true)
    * `:module_filter` - only include nodes matching this module prefix

  ## Returns

  `{:ok, d3_data}` or `{:error, reason}`
  """
  @spec fetch_d3_data(keyword()) :: {:ok, d3_data()} | {:error, term()}
  def fetch_d3_data(opts \\ []) do
    max_nodes = Keyword.get(opts, :max_nodes, 500)
    include_communities = Keyword.get(opts, :include_communities, true)
    module_filter = Keyword.get(opts, :module_filter)

    with {:ok, base} <-
           Algorithms.export_d3_json(
             max_nodes: max_nodes,
             include_communities: include_communities
           ) do
      # Enrich nodes with additional metrics
      betweenness = safe_betweenness(max_nodes)

      nodes =
        base.nodes
        |> Enum.map(fn node ->
          node
          |> Map.put(:betweenness, Map.get(betweenness, node.id, 0.0))
          |> Map.put(:label, node_label(node))
          |> Map.put(:module_name, extract_module(node.id))
        end)
        |> maybe_filter_module(module_filter)

      # Filter links to only include visible nodes
      node_ids = MapSet.new(nodes, & &1.id)

      links =
        Enum.filter(base.links, fn link ->
          MapSet.member?(node_ids, link.source) and MapSet.member?(node_ids, link.target)
        end)

      # Community data for hull rendering
      communities = build_community_map(nodes)

      stats = %{
        total_nodes: length(nodes),
        total_links: length(links),
        community_count: map_size(communities)
      }

      {:ok, %{nodes: nodes, links: links, communities: communities, stats: stats}}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Returns detailed information about a specific node.

  Used when a user clicks a node in the graph to show the detail panel.

  ## Returns

  A map with `:id`, `:type`, `:module`, `:name`, `:arity`, `:file`,
  `:metrics`, `:callers`, `:callees`, or `nil` if not found.
  """
  @spec node_details(String.t()) :: map() | nil
  def node_details(node_id_string) do
    # Try to find the node by looking up all nodes and matching the string ID
    Store.list_nodes(nil, :infinity)
    |> Enum.find_value(fn node ->
      if format_id(node) == node_id_string do
        build_node_details(node, node_id_string)
      end
    end)
  rescue
    _ -> nil
  end

  @doc """
  Returns available metrics with their display names.
  """
  @spec available_metrics() :: [{metric(), String.t()}]
  def available_metrics do
    [
      {:pagerank, "PageRank"},
      {:betweenness, "Betweenness"},
      {:degree, "Degree"},
      {:community, "Community"}
    ]
  end

  @doc """
  Exports the current graph as Graphviz DOT format.
  """
  @spec export_dot(keyword()) :: {:ok, String.t()} | {:error, term()}
  def export_dot(opts \\ []) do
    Algorithms.export_graphviz(opts)
  end

  # -- Private --

  defp safe_betweenness(max_nodes) do
    Algorithms.betweenness_centrality(max_nodes: min(max_nodes, 200))
    |> Map.new(fn {k, v} -> {format_node_id(k), v} end)
  rescue
    _ -> %{}
  end

  defp format_node_id({:function, mod, name, arity}), do: "#{mod}.#{name}/#{arity}"
  defp format_node_id({:module, name}), do: "#{name}"
  defp format_node_id(other), do: inspect(other)

  defp format_id(%{type: :function, id: {mod, name, arity}}), do: "#{mod}.#{name}/#{arity}"
  defp format_id(%{type: :module, id: name}), do: "#{name}"
  defp format_id(%{type: type, id: id}), do: "#{type}:#{inspect(id)}"

  defp node_label(%{id: id, type: "function"}) do
    case String.split(id, ".") do
      [_mod, func_part] -> func_part
      _ -> id
    end
  end

  defp node_label(%{id: id, type: "module"}) do
    id |> String.split(".") |> List.last()
  end

  defp node_label(%{id: id}), do: id

  defp extract_module(id) when is_binary(id) do
    case String.split(id, ".") do
      [mod | _rest] when byte_size(mod) > 0 -> mod
      _ -> id
    end
  end

  defp maybe_filter_module(nodes, nil), do: nodes

  defp maybe_filter_module(nodes, prefix) when is_binary(prefix) and prefix != "" do
    Enum.filter(nodes, fn node ->
      String.starts_with?(node.id, prefix)
    end)
  end

  defp maybe_filter_module(nodes, _), do: nodes

  defp build_community_map(nodes) do
    nodes
    |> Enum.group_by(& &1.community)
    |> Map.delete(nil)
    |> Map.new(fn {community_id, members} ->
      {to_string(community_id), Enum.map(members, & &1.id)}
    end)
  end

  defp build_node_details(node, node_id_string) do
    {type, id} = {node.type, node.id}
    data = node[:data] || %{}

    # Get callers and callees
    node_key =
      case {type, id} do
        {:function, {mod, name, arity}} -> {:function, mod, name, arity}
        {:module, name} -> {:module, name}
        _ -> {type, id}
      end

    callers =
      Store.get_incoming_edges(node_key, :calls)
      |> Enum.map(fn edge -> format_node_id(edge.from) end)
      |> Enum.take(20)

    callees =
      Store.get_outgoing_edges(node_key, :calls)
      |> Enum.map(fn edge -> format_node_id(edge.to) end)
      |> Enum.take(20)

    # Build metrics
    metrics = %{
      callers_count: length(callers),
      callees_count: length(callees)
    }

    %{
      id: node_id_string,
      type: to_string(type),
      file: Map.get(data, :file),
      line: Map.get(data, :line),
      name: extract_name(type, id),
      module: extract_module_from_id(type, id),
      arity: extract_arity(type, id),
      metrics: metrics,
      callers: callers,
      callees: callees
    }
  end

  defp extract_name(:function, {_mod, name, _arity}), do: to_string(name)
  defp extract_name(:module, name), do: to_string(name)
  defp extract_name(_, id), do: inspect(id)

  defp extract_module_from_id(:function, {mod, _, _}), do: to_string(mod)
  defp extract_module_from_id(:module, name), do: to_string(name)
  defp extract_module_from_id(_, _), do: nil

  defp extract_arity(:function, {_, _, arity}), do: arity
  defp extract_arity(_, _), do: nil
end
