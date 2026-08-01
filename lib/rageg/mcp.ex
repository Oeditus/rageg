defmodule Rageg.MCP do
  @moduledoc """
  Context module for inspecting and executing Ragex Model Context Protocol (MCP) tools.

  Wraps `Ragex.MCP.Handlers.Tools` to list available tool definitions, schemas,
  and execute tools with arbitrary parameter payloads.
  """

  @type tool_schema :: %{
          name: String.t(),
          description: String.t(),
          inputSchema: map()
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
  """
  @spec list_tools() :: [tool_schema()]
  def list_tools do
    res = Ragex.MCP.Handlers.Tools.list_tools()
    Map.get(res, :tools, [])
  rescue
    _ -> []
  end

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

    res = Ragex.MCP.Handlers.Tools.call_tool(tool_name, arguments)

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
  Filters the list of MCP tools matching a query string.
  """
  @spec filter_tools([tool_schema()], String.t()) :: [tool_schema()]
  def filter_tools(tools, query) when is_list(tools) and is_binary(query) do
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
