defmodule Rageg.MCPTest do
  use ExUnit.Case, async: true

  alias Rageg.MCP

  describe "list_tools/0" do
    test "returns a non-empty list of exported MCP tools" do
      tools = MCP.list_tools()
      assert is_list(tools)
      assert length(tools) > 0

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

  describe "filter_tools/2" do
    test "filters tools by query string" do
      tools = MCP.list_tools()
      filtered = MCP.filter_tools(tools, "search")

      assert is_list(filtered)

      assert Enum.all?(filtered, fn t ->
               String.contains?(String.downcase(t.name), "search") or
                 String.contains?(String.downcase(t.description), "search")
             end)
    end
  end
end
