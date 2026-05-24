defmodule RagegWeb.GraphLiveTest do
  use RagegWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /graph" do
    test "renders the graph explorer page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/graph")

      assert html =~ "Knowledge Graph"
      assert html =~ "graph-container"
      assert html =~ "GraphHook"
    end

    test "shows metric selector buttons", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/graph")

      assert html =~ "PageRank"
      assert html =~ "Betweenness"
      assert html =~ "Degree"
      assert html =~ "Community"
    end

    test "shows filter input and max nodes slider", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/graph")

      assert html =~ "module_filter"
      assert html =~ "max_nodes"
    end

    test "shows export buttons", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/graph")

      assert html =~ "export_svg"
      assert html =~ "export_dot"
      assert html =~ "refresh_graph"
    end

    test "change_metric event updates metric assign", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/graph")

      html = render_click(view, "change_metric", %{"metric" => "community"})
      assert html =~ "btn-primary"
    end

    test "node_selected shows detail panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/graph")

      # Simulate a node selection (even though the node won't be found,
      # the handler should not crash)
      html = render_click(view, "node_selected", %{"node_id" => "SomeModule.func/2"})
      # Detail panel shouldn't appear since node doesn't exist
      refute html =~ "node_detail_panel"
    end

    test "node_deselected clears the detail panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/graph")

      render_click(view, "node_deselected", %{})
      html = render(view)

      # No detail panel visible
      refute html =~ "Called by"
    end
  end
end
