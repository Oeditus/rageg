defmodule Rageg.MCP do
  @moduledoc """
  Context module for inspecting and executing Ragex Model Context Protocol (MCP) tools.

  Wraps `Ragex.MCP.Handlers.Tools` to list available tool definitions, schemas,
  and execute tools with arbitrary parameter payloads.
  """

  alias Ragex.Agent.ToolSchema
  alias Ragex.MCP.Handlers.Prompts, as: MCPPrompts
  alias Ragex.MCP.Handlers.Resources, as: MCPResources
  alias Ragex.MCP.Handlers.Tools, as: MCPTools
  alias Ragex.MCP.SocketPath, as: MCPSocketPath

  @type tool_schema :: %{
          name: String.t(),
          description: String.t(),
          inputSchema: map(),
          destruction_level: atom() | String.t()
        }

  @type execution_result :: %{
          tool: String.t(),
          arguments: map(),
          output: String.t() | map(),
          is_error: boolean(),
          timing_ms: non_neg_integer()
        }

  @doc """
  Lists all exported Ragex MCP tools.

  Each tool's `inputSchema` is normalised to the canonical MCP JSON-schema
  shape (string keys, e.g. `"type"`, `"default"`, `"enum"`, `"required"`)
  so UI consumers can render forms regardless of how the underlying Ragex
  layer represents the schema (atom-keyed Elixir maps vs. JSON string keys).
  Deduplicates tools by name to ensure clean DOM element identity.
  """
  @spec list_tools() :: [tool_schema()]
  def list_tools do
    res = MCPTools.list_tools()

    res
    |> Map.get(:tools, [])
    |> Enum.map(&normalize_tool_schema/1)
    |> Enum.uniq_by(fn t -> t[:name] || t["name"] end)
  rescue
    e -> Rageg.Diagnostics.suppressed(:mcp_list_tools, e, [])
  end

  # Normalize every tool to a single canonical shape so UI consumers can rely
  # on one convention: the envelope keeps atom keys (`:inputSchema`,
  # `:destruction_level`) and the schema itself is recursively stringified so
  # property specs (`type`, `default`, `enum`, `description`, `required`) are
  # always readable via string keys. This is exactly the shape that
  # `RagegWeb.McpLive.get_schema_properties/1` expects.
  defp normalize_tool_schema(tool) when is_map(tool) do
    schema = Map.get(tool, :inputSchema) || Map.get(tool, "inputSchema") || %{}

    level =
      normalize_destruction_level(
        Map.get(tool, :destruction_level) || Map.get(tool, "destruction_level") || :none
      )

    tool
    |> Map.drop([:inputSchema, "inputSchema", :destruction_level, "destruction_level"])
    |> Map.put(:inputSchema, stringify_keys(schema))
    |> Map.put(:destruction_level, level)
  end

  defp normalize_tool_schema(tool), do: tool

  defp normalize_destruction_level(level) when is_atom(level) do
    case level do
      :none -> :none
      :low -> :low
      :medium -> :medium
      :high -> :high
      :full -> :full
      _ -> :none
    end
  end

  defp normalize_destruction_level(level) when is_binary(level) do
    case level do
      "none" -> :none
      "low" -> :low
      "medium" -> :medium
      "high" -> :high
      "full" -> :full
      _ -> :none
    end
  end

  defp normalize_destruction_level(_), do: :none

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(other), do: other

  @doc """
  Finds a specific tool schema by name.
  """
  @spec get_tool(String.t()) :: tool_schema() | nil
  def get_tool(tool_name) when is_binary(tool_name) do
    Enum.find(list_tools(), &(&1.name == tool_name))
  end

  @doc """
  Executes an MCP tool by name with arguments map.
  """
  @spec call_tool(String.t(), map()) :: {:ok, execution_result()} | {:error, term()}
  def call_tool(tool_name, arguments \\ %{}) when is_binary(tool_name) and is_map(arguments) do
    start_time = System.monotonic_time(:millisecond)

    res = MCPTools.call_tool(tool_name, arguments)

    elapsed_ms = System.monotonic_time(:millisecond) - start_time

    case res do
      %{content: content_list} when is_list(content_list) ->
        is_error = Map.get(res, :isError, false)
        text_output = extract_text_content(content_list)

        {:ok,
         %{
           tool: tool_name,
           arguments: arguments,
           output: text_output,
           is_error: is_error,
           timing_ms: elapsed_ms
         }}

      {:ok, result} ->
        {:ok,
         %{
           tool: tool_name,
           arguments: arguments,
           output: result,
           is_error: false,
           timing_ms: elapsed_ms
         }}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:ok,
         %{
           tool: tool_name,
           arguments: arguments,
           output: inspect(other),
           is_error: false,
           timing_ms: elapsed_ms
         }}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Returns the Unix Domain Socket path computed by `Ragex.MCP.SocketPath`.
  """
  @spec socket_path() :: String.t()
  def socket_path do
    MCPSocketPath.compute_string()
  rescue
    e -> Rageg.Diagnostics.suppressed(:mcp_socket_path, e, "/tmp/ragex_mcp.sock")
  end

  @doc """
  Lists all available MCP resources exported by Ragex.
  """
  @spec list_resources() :: [map()]
  def list_resources do
    res = MCPResources.list_resources()
    Map.get(res, :resources, [])
  rescue
    _ -> []
  end

  @doc """
  Reads a specific MCP resource by URI.
  """
  @spec read_resource(String.t()) :: {:ok, term()} | {:error, term()}
  def read_resource(uri) when is_binary(uri) do
    MCPResources.read_resource(uri)
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Lists all available MCP prompts exported by Ragex.
  """
  @spec list_prompts() :: [map()]
  def list_prompts do
    res = MCPPrompts.list_prompts()
    Map.get(res, :prompts, [])
  rescue
    _ -> []
  end

  @doc """
  Returns the 10 read-only RAG query tool names.
  """
  @spec rag_tool_names() :: [String.t()]
  def rag_tool_names do
    ToolSchema.rag_tool_names()
  rescue
    _ ->
      [
        "read_file",
        "semantic_search",
        "hybrid_search",
        "query_graph",
        "list_nodes",
        "find_callers",
        "find_paths",
        "find_circular_dependencies",
        "coupling_report",
        "graph_stats"
      ]
  end

  @doc """
  Filters the list of MCP tools matching a query string and category filter.
  """
  @spec filter_tools([tool_schema()], String.t(), String.t() | atom()) :: [tool_schema()]
  def filter_tools(tools, query, category \\ "all")

  def filter_tools(tools, query, category) when is_list(tools) and is_binary(query) do
    cat_str = to_string(category)

    tools
    |> Enum.filter(&matches_category?(&1, cat_str))
    |> filter_by_query(query)
  end

  defp filter_by_query(tools, query) do
    q = String.downcase(String.trim(query))

    if q == "" do
      tools
    else
      Enum.filter(tools, fn t ->
        name = String.downcase(t.name || "")
        desc = String.downcase(t.description || "")
        String.contains?(name, q) or String.contains?(desc, q)
      end)
    end
  end

  defp matches_category?(_tool, "all"), do: true

  defp matches_category?(tool, "rag") do
    tool.name in rag_tool_names()
  end

  defp matches_category?(tool, "git") do
    String.starts_with?(tool.name, "git_") or String.starts_with?(tool.name, "co_change_")
  end

  defp matches_category?(tool, "image") do
    String.starts_with?(tool.name, "image_")
  end

  defp matches_category?(tool, "scip") do
    String.starts_with?(tool.name, "scip_")
  end

  defp matches_category?(tool, "refactor") do
    name = tool.name

    String.contains?(name, "refactor") or String.contains?(name, "edit") or
      String.contains?(name, "preview") or String.contains?(name, "rollback") or
      String.contains?(name, "undo")
  end

  defp matches_category?(tool, "quality") do
    name = tool.name

    String.contains?(name, "quality") or String.contains?(name, "security") or
      String.contains?(name, "smell") or String.contains?(name, "dead_code") or
      String.contains?(name, "duplicate") or String.contains?(name, "complexity") or
      String.contains?(name, "business_logic")
  end

  defp matches_category?(tool, "url") do
    String.contains?(tool.name, "url") or String.contains?(tool.name, "web")
  end

  defp matches_category?(tool, "plugins") do
    Map.has_key?(tool, :plugin_id) or Map.has_key?(tool, "plugin_id") or
      tool.name in [
        "analyze_url",
        "git_blame",
        "git_history",
        "git_pr_info",
        "co_change_analysis",
        "git_enrich"
      ]
  end

  defp matches_category?(_tool, _category), do: true

  # Helpers

  defp extract_text_content(content_list) do
    texts =
      Enum.flat_map(content_list, fn
        %{text: t} when is_binary(t) -> [t]
        %{"text" => t} when is_binary(t) -> [t]
        item -> [inspect(item)]
      end)

    Enum.join(texts, "\n\n")
  end
end
