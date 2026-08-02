defmodule RagegWeb.McpLiveTest do
  use RagegWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "GET /mcp" do
    test "renders MCP Tools Runner page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/mcp")

      assert html =~ "MCP Tools Runner"
      assert html =~ "Interactively execute exported Ragex Model Context Protocol"
    end

    test "displays interactive tool selection list and executor form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/mcp")

      assert has_element?(view, "#mcp-search-input")
      assert has_element?(view, "#mcp-tools-list")
      assert has_element?(view, "#mcp-executor-card")
      assert has_element?(view, "#mcp-execute-btn")
    end

    test "selects a tool from list and updates form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/mcp")

      html = render_click(view, "select_tool", %{"name" => "list_nodes"})
      assert html =~ "list_nodes"
    end

    test "switches mode between form and JSON payload", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/mcp")

      _html1 = render_click(view, "switch_mode", %{"mode" => "json"})
      assert has_element?(view, "#mcp-json-textarea")

      _html2 = render_click(view, "switch_mode", %{"mode" => "form"})
      refute has_element?(view, "#mcp-json-textarea")
    end

    test "executes tool call and displays result", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/mcp")

      render_click(view, "select_tool", %{"name" => "list_nodes"})
      render_click(view, "execute_tool", %{})

      html = render(view)
      assert html =~ "Tool Result"
      assert has_element?(view, "#mcp-result-card")
    end
  end
end
