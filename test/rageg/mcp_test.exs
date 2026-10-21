defmodule Rageg.MCPTest do
  use ExUnit.Case, async: true

  alias Rageg.MCP

  describe "list_tools/0" do
    test "returns a non-empty list of exported MCP tools" do
      tools = MCP.list_tools()
      assert is_list(tools)
      assert tools != []

      first = List.first(tools)
      assert is_binary(first.name)
      assert is_binary(first.description)
    end
  end

  describe "get_tool/1" do
    test "retrieves tool schema by name" do
      tool = MCP.get_tool("list_nodes")
      assert tool != nil
      assert tool.name == "list_nodes"
    end

    test "returns nil for non-existent tool" do
      assert MCP.get_tool("nonexistent_tool_123") == nil
    end
  end

  describe "call_tool/2" do
    test "executes a known MCP tool" do
      {:ok, result} = MCP.call_tool("list_nodes", %{})
      assert result.tool == "list_nodes"
      assert is_integer(result.timing_ms)
      assert is_boolean(result.is_error)
    end
  end

  describe "socket_path/0" do
    test "returns the Unix domain socket path string" do
      path = MCP.socket_path()
      assert is_binary(path)
      assert String.contains?(path, "ragex_mcp") or String.contains?(path, ".sock")
    end
  end

  describe "list_resources/0" do
    test "returns exported MCP resources" do
      resources = MCP.list_resources()
      assert is_list(resources)
      assert resources != []
      first = List.first(resources)
      assert Map.has_key?(first, :uri) or Map.has_key?(first, "uri")
    end
  end

  describe "list_prompts/0" do
    test "returns exported MCP prompts" do
      prompts = MCP.list_prompts()
      assert is_list(prompts)
    end
  end

  describe "rag_tool_names/0" do
    test "returns 10 RAG tool names" do
      names = MCP.rag_tool_names()
      assert is_list(names)
      assert length(names) == 10
      assert "read_file" in names
      assert "hybrid_search" in names
    end
  end

  describe "normalize_tool_schema/1 (via list_tools/0)" do
    test "inputSchema uses string keys" do
      for tool <- MCP.list_tools() do
        assert is_map(tool.inputSchema)
        assert Enum.all?(Map.keys(tool.inputSchema), &is_binary/1)
      end
    end

    test "at least one tool exposes properties readable via string keys" do
      tool =
        Enum.find(MCP.list_tools(), fn t ->
          map_size(Map.get(t.inputSchema, "properties") || %{}) > 0
        end)

      assert tool != nil
      assert is_map(Map.get(tool.inputSchema, "properties"))
    end
  end

  describe "filter_tools/3" do
    test "filters tools by query string" do
      tools = MCP.list_tools()
      filtered = MCP.filter_tools(tools, "search")

      assert is_list(filtered)

      assert Enum.all?(filtered, fn t ->
               String.contains?(String.downcase(t.name), "search") or
                 String.contains?(String.downcase(t.description), "search")
             end)
    end

    test "filters tools by category" do
      tools = MCP.list_tools()
      rag_tools = MCP.filter_tools(tools, "", "rag")
      assert is_list(rag_tools)
      assert Enum.all?(rag_tools, fn t -> t.name in MCP.rag_tool_names() end)
    end
  end
end
