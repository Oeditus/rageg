defmodule RagegWeb.McpLiveTest do
  use RagegWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "GET /mcp" do
    test "renders MCP Tools Runner page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/mcp")

      assert html =~ "MCP Tools"
      assert html =~ "Interactively execute MCP tools"
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

    test "search input is wired to send typed values", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/mcp")
      assert has_element?(view, ~s|#mcp-search-input[name="query"]|)
    end

    test "executes tool call and displays result", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/mcp")

      render_click(view, "select_tool", %{"name" => "list_nodes"})
      render_click(view, "execute_tool", %{})

      # Tool execution is async (spawned Task -> handle_info), so poll until
      # the result card is rendered or we time out.
      html = wait_for_result(view)
      assert html =~ "Tool Result"
      assert has_element?(view, "#mcp-result-card")
    end
  end

  describe "destructive tool confirmation" do
    test "read-only tools run without a confirmation step", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/mcp")

      render_click(view, "select_tool", %{"name" => "list_nodes"})
      render_click(view, "execute_tool", %{})

      refute has_element?(view, "#mcp-confirm-overlay")
    end

    test "a pending confirmation can be cancelled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/mcp")

      # Pretend the selected tool is destructive and ask to execute it.
      destructive = %{
        name: "refactor_demo",
        description: "demo",
        inputSchema: %{"type" => "object", "properties" => %{}},
        destruction_level: :full
      }

      :sys.replace_state(view.pid, fn %{socket: socket} = state ->
        Map.put(state, :socket, Phoenix.Component.assign(socket, :selected_tool, destructive))
      end)

      html = render_click(view, "execute_tool", %{})
      assert html =~ "Confirm destructive tool"
      assert has_element?(view, "#mcp-confirm-run")

      html = render_click(view, "cancel_execute", %{})
      refute html =~ "Confirm destructive tool"
    end

    test "offers a dry-run toggle only when the tool declares dry_run", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/mcp")

      with_dry_run = %{
        name: "edit_demo",
        description: "demo",
        inputSchema: %{
          "type" => "object",
          "properties" => %{"dry_run" => %{"type" => "boolean"}}
        },
        destruction_level: :high
      }

      :sys.replace_state(view.pid, fn %{socket: socket} = state ->
        Map.put(state, :socket, Phoenix.Component.assign(socket, :selected_tool, with_dry_run))
      end)

      html = render_click(view, "execute_tool", %{})
      assert has_element?(view, "#mcp-dry-run-toggle")
      assert html =~ "Run dry run"

      html = render_click(view, "toggle_dry_run", %{})
      assert html =~ "Execute anyway"
    end
  end

  # Renders the view repeatedly until the async tool result appears, or until
  # `deadline` is reached (defaults to a generous 5s). Returns the final html.
  defp wait_for_result(view, deadline \\ System.monotonic_time(:millisecond) + 5_000) do
    html = render(view)

    if html =~ "Tool Result" or System.monotonic_time(:millisecond) >= deadline do
      html
    else
      Process.sleep(20)
      wait_for_result(view, deadline)
    end
  end
end
