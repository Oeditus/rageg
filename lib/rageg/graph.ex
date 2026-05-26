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

  require Logger

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
    t0 = System.monotonic_time(:millisecond)
    max_nodes = Keyword.get(opts, :max_nodes, 500)
    include_communities = Keyword.get(opts, :include_communities, true)
    module_filter = Keyword.get(opts, :module_filter)

    with {:ok, base} <-
           timed(:export_d3_json, fn ->
             result =
               Algorithms.export_d3_json(
                 max_nodes: max_nodes,
                 include_communities: include_communities
               )

             case result do
               {:ok, data} ->
                 Logger.info(
                   "[graph:export_d3_json] raw nodes=#{length(data.nodes)} raw links=#{length(data.links)}"
                 )

                 {:ok, data}

               other ->
                 other
             end
           end) do
      # Build lookup from dllb record IDs to human-readable Module.fun/arity names.
      dllb_name_lookup =
        timed(:name_lookup, fn ->
          lookup = build_dllb_name_lookup()
          Logger.info("[graph:name_lookup] #{map_size(lookup)} name entries")
          lookup
        end)

      # Enrich nodes with additional metrics
      betweenness =
        timed(:betweenness, fn ->
          b = safe_betweenness(max_nodes)
          Logger.info("[graph:betweenness] #{map_size(b)} centrality scores")
          b
        end)

      nodes =
        timed(:enrich_nodes, fn ->
          {enriched, miss_count} =
            base.nodes
            |> Enum.map_reduce(0, fn node, misses ->
              {pretty_id, source} = resolve_pretty_id(node.id, dllb_name_lookup)

              misses =
                if source == :prettify do
                  if misses < 5 do
                    Logger.warning(
                      "[graph:name_miss] id=#{inspect(node.id)} " <>
                        "type=#{node.type} prettified=#{inspect(pretty_id)}"
                    )
                  end

                  misses + 1
                else
                  misses
                end

              enriched =
                node
                |> Map.put(:id, pretty_id)
                |> Map.put(
                  :betweenness,
                  Map.get(betweenness, node.id, 0.0) || Map.get(betweenness, pretty_id, 0.0)
                )
                |> Map.put(:label, node_label(%{node | id: pretty_id}))
                |> Map.put(:module_name, extract_module(pretty_id))

              {enriched, misses}
            end)

          total = length(enriched)
          hits = total - miss_count

          Logger.info(
            "[graph:name_resolution] total=#{total} lookup_hits=#{hits} prettify_fallbacks=#{miss_count}"
          )

          enriched |> maybe_filter_module(module_filter)
        end)

      # Filter links to only include visible nodes
      {links, communities, stats} =
        timed(:build_links, fn ->
          node_ids = MapSet.new(nodes, & &1.id)

          original_to_pretty =
            base.nodes
            |> Map.new(fn node ->
              pretty =
                Map.get(dllb_name_lookup, node.id) ||
                  Map.get(dllb_name_lookup, String.replace_prefix(node.id, "ast_node:", "")) ||
                  prettify_id(node.id)

              {node.id, pretty}
            end)

          links =
            base.links
            |> Enum.map(fn link ->
              %{
                link
                | source: Map.get(original_to_pretty, link.source, prettify_id(link.source)),
                  target: Map.get(original_to_pretty, link.target, prettify_id(link.target))
              }
            end)
            |> Enum.filter(fn link ->
              MapSet.member?(node_ids, link.source) and MapSet.member?(node_ids, link.target)
            end)

          communities = build_community_map(nodes)

          stats = %{
            total_nodes: length(nodes),
            total_links: length(links),
            community_count: map_size(communities)
          }

          Logger.info(
            "[graph:build_links] visible nodes=#{stats.total_nodes} links=#{stats.total_links} communities=#{stats.community_count}"
          )

          {links, communities, stats}
        end)

      total_ms = System.monotonic_time(:millisecond) - t0

      Logger.info(
        "[graph:total] #{total_ms}ms nodes=#{stats.total_nodes} links=#{stats.total_links}"
      )

      {:ok, %{nodes: nodes, links: links, communities: communities, stats: stats}}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp timed(label, fun) do
    t0 = System.monotonic_time(:millisecond)
    result = fun.()
    elapsed = System.monotonic_time(:millisecond) - t0
    Logger.info("[graph:#{label}] #{elapsed}ms")
    result
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
    # Try to find the node by matching both the raw and prettified string ID
    Store.list_nodes(nil, :infinity)
    |> Enum.find_value(fn node ->
      raw = format_id(node)

      if raw == node_id_string or prettify_id(raw) == node_id_string do
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

  # Builds a map from dllb record ID -> "Module.fun/arity" by querying
  # all nodes from the store and extracting their structured metadata.
  defp build_dllb_name_lookup do
    Store.list_nodes(nil, :infinity)
    |> Enum.flat_map(fn n ->
      data = n[:data] || %{}
      dllb_id = data[:id]
      kind = data[:kind] || n.type

      mod = data[:module] |> to_nil_string() |> maybe_strip_elixir()
      name = (data[:name] || n.id) |> to_nil_string()
      arity = data[:arity]

      human_name =
        case kind do
          k when k in [:function_def, "function_def"] ->
            format_human_name(mod, name, arity)

          k when k in [:function_call, "function_call"] ->
            # function_call nodes never have arity; show Module.fun
            format_human_name(mod, name, nil)

          k when k in [:container, "container"] ->
            maybe_strip_elixir(to_string(data[:name] || n.id))

          _ ->
            # For any other kind (import, variable, etc.) include module if present
            format_human_name(mod, name, arity)
        end

      # Index by both the full dllb ID and the bare ID (without ast_node: prefix)
      entries = [{to_string(n.id), human_name}]

      entries =
        if dllb_id do
          bare = String.replace_prefix(to_string(dllb_id), "ast_node:", "")
          [{to_string(dllb_id), human_name}, {bare, human_name} | entries]
        else
          entries
        end

      # Also index by the reconstructed MetaAST file-based ID
      # (format: "ast_node:file_stem_name_line") so lookups succeed even when
      # the raw row[:id] format differs from what export_d3_json returns.
      entries =
        case reconstruct_meta_ast_id(data) do
          nil -> entries
          meta_id -> [{meta_id, human_name} | entries]
        end

      entries
    end)
    |> Map.new()
  end

  # Reconstructs the MetaAST node ID from stored metadata fields, matching
  # the format produced by Dllb.MetaAST.node_id/3:
  #   "ast_node:<file_stem>_<sanitized_name>_<line>"
  defp reconstruct_meta_ast_id(data) do
    file_path = data[:file_path]
    name = data[:name]
    line = data[:line_start] || 0

    if file_path && name do
      file_stem =
        file_path
        |> Path.basename()
        |> Path.rootname()
        |> String.replace(~r/[^a-zA-Z0-9_]/, "_")

      sanitized_name = to_string(name) |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      "ast_node:#{file_stem}_#{sanitized_name}_#{line}"
    end
  end

  # Formats a human-readable name from module/name/arity components.
  # Always includes module prefix when available.
  defp format_human_name(nil, nil, _arity), do: "?"
  defp format_human_name(nil, name, nil), do: name
  defp format_human_name(nil, name, arity), do: "#{name}/#{arity}"
  defp format_human_name(mod, nil, _arity), do: mod
  defp format_human_name(mod, name, nil), do: "#{mod}.#{name}"
  defp format_human_name(mod, name, arity), do: "#{mod}.#{name}/#{arity}"

  defp to_nil_string(nil), do: nil
  defp to_nil_string(val), do: to_string(val)

  defp maybe_strip_elixir(nil), do: nil
  defp maybe_strip_elixir(name), do: strip_elixir(name)

  defp strip_elixir(name) when is_binary(name), do: String.replace_prefix(name, "Elixir.", "")
  defp strip_elixir(name), do: to_string(name) |> strip_elixir()

  # Resolves a D3 node ID to a human-readable name, returning the
  # source of resolution (:dllb_full, :dllb_bare, or :prettify).
  defp resolve_pretty_id(raw_id, lookup) do
    cond do
      name = Map.get(lookup, raw_id) ->
        {name, :dllb_full}

      name = Map.get(lookup, String.replace_prefix(raw_id, "ast_node:", "")) ->
        {name, :dllb_bare}

      true ->
        {prettify_id(raw_id), :prettify}
    end
  end

  defp safe_betweenness(max_nodes) do
    Algorithms.betweenness_centrality(max_nodes: min(max_nodes, 200))
    |> Map.new(fn {k, v} -> {format_node_id(k), v} end)
  rescue
    _ -> %{}
  end

  defp format_node_id({:function, mod, name, arity}), do: "#{mod}.#{name}/#{arity}"
  defp format_node_id({:module, name}), do: "#{name}"
  defp format_node_id(other) when is_binary(other), do: other
  defp format_node_id(other), do: inspect(other)

  defp format_id(%{type: :function, id: {mod, name, arity}}), do: "#{mod}.#{name}/#{arity}"
  defp format_id(%{type: :module, id: name}), do: "#{name}"
  # dllb backend returns string types ("function", "module") and string IDs
  defp format_id(%{type: "function", id: id}) when is_binary(id), do: id
  defp format_id(%{type: "module", id: id}) when is_binary(id), do: id
  defp format_id(%{type: type, id: id}) when is_binary(id), do: "#{type}:#{id}"
  defp format_id(%{type: type, id: id}), do: "#{type}:#{inspect(id)}"

  @doc false
  @spec prettify_id(String.t()) :: String.t()
  def prettify_id(id) when is_binary(id) do
    result =
      cond do
        # Already in Module.fun/arity format
        Regex.match?(~r/^[A-Z][\w.]*\.\w+\/\d+$/, id) ->
          id

        # Already a clean module name
        Regex.match?(~r/^[A-Z][\w.]*$/, id) ->
          id

        # Inspected 4-tuple: {:type, Module, :name, arity}
        match = Regex.run(~r/^\{:\w+,\s*([^,]+),\s*:?(\w+),\s*(\d+)\}$/, id) ->
          [_, mod_raw, name, arity] = match
          mod = mod_raw |> String.trim() |> String.replace_prefix("Elixir.", "")
          "#{mod}.#{name}/#{arity}"

        # Inspected 2-tuple: {:type, Module}
        match = Regex.run(~r/^\{:\w+,\s*([A-Z][\w.]*)\}$/, id) ->
          [_, mod] = match
          String.replace_prefix(mod, "Elixir.", "")

        # Colon-separated format: type:rest_Module_fun_N
        match = Regex.run(~r/^\w+:(.+)$/, id) ->
          [_, rest] = match
          parse_underscore_encoded(rest)

        true ->
          id
      end

    # Always strip the "Elixir." prefix from the final result
    String.replace_prefix(result, "Elixir.", "")
  end

  # Parses underscore-encoded identifiers like "access_Kernel_max_2"
  # into "Kernel.max/2" by detecting capitalized module segments.
  defp parse_underscore_encoded(rest) do
    parts = String.split(rest, "_")

    # Find the first capitalized part (module start)
    case Enum.split_while(parts, fn p -> not String.match?(p, ~r/^[A-Z]/) end) do
      {_prefix, []} ->
        rest

      {_prefix, mod_and_rest} ->
        # Split: capitalized segments = module, then lowercase = fun, trailing digit = arity
        {mod_parts, after_mod} =
          Enum.split_while(mod_and_rest, fn p -> String.match?(p, ~r/^[A-Z]/) end)

        module = Enum.join(mod_parts, ".")

        case after_mod do
          [] ->
            module

          _ ->
            # Last element might be arity (pure digits) or line number
            {fun_parts, maybe_arity} =
              case Integer.parse(List.last(after_mod)) do
                {n, ""} when n < 256 ->
                  {Enum.drop(after_mod, -1), "/#{n}"}

                _ ->
                  {after_mod, ""}
              end

            fun_name = Enum.join(fun_parts, "_")

            if fun_name == "" do
              "#{module}#{maybe_arity}"
            else
              "#{module}.#{fun_name}#{maybe_arity}"
            end
        end
    end
  end

  defp node_label(%{id: id, type: "function"}) do
    pretty = prettify_id(id)
    parts = String.split(pretty, ".")

    case parts do
      [_single] ->
        # Already no module prefix; return as-is
        pretty

      _ ->
        # Build "LastMod.fun/arity" — keep the last module segment so the
        # label conforms to the Mod.fun/arity pattern without overwhelming
        # the graph with fully-qualified multi-segment paths.
        [func_part | rev_mods] = Enum.reverse(parts)
        last_mod = hd(rev_mods)
        "#{last_mod}.#{func_part}"
    end
  end

  defp node_label(%{id: id, type: "module"}) do
    prettify_id(id) |> String.split(".") |> List.last()
  end

  defp node_label(%{id: id}), do: prettify_id(id)

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
      |> Enum.map(fn edge -> edge.from |> format_node_id() |> prettify_id() end)
      |> Enum.take(20)

    callees =
      Store.get_outgoing_edges(node_key, :calls)
      |> Enum.map(fn edge -> edge.to |> format_node_id() |> prettify_id() end)
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
