defmodule RagegWeb.DashboardLiveTest do
  use RagegWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /" do
    test "renders the dashboard page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      # Page title
      assert html =~ "Dashboard"

      # All stat sections present
      assert html =~ "Knowledge Graph"
      assert html =~ "Embeddings"
      assert html =~ "AI Cache"
      assert html =~ "AI Usage"
      assert html =~ "dllb Backend"
    end

    test "displays stat card labels", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Nodes"
      assert html =~ "Edges"
      assert html =~ "Density"
      assert html =~ "Hit Rate"
      assert html =~ "Tokens"
    end

    test "updates stats via PubSub", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Simulate a stats update
      updated_stats = %{
        Rageg.Stats.empty_snapshot()
        | graph: %{nodes: 42, edges: 100, density: 0.123, components: 3}
      }

      Phoenix.PubSub.broadcast(Rageg.PubSub, Rageg.Stats.topic(), {:stats_updated, updated_stats})

      # The view should re-render with the new values
      html = render(view)
      assert html =~ "42"
      assert html =~ "100"
    end
  end
end
