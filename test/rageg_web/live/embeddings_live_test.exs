defmodule RagegWeb.EmbeddingsLiveTest do
  use RagegWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /embeddings" do
    test "renders embedding space page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/embeddings")

      assert html =~ "Embedding Space"
      assert html =~ "scatter-container"
      assert html =~ "ScatterHook"
      assert html =~ "Semantic search"
    end

    test "shows type legend", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/embeddings")

      assert html =~ "function"
      assert html =~ "module"
    end

    test "search event does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/embeddings")

      html = render_click(view, "search", %{"query" => "test"})
      assert html =~ "Embedding Space"
    end

    test "point_deselected clears selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/embeddings")

      html = render_click(view, "point_deselected", %{})
      refute html =~ "Nearest Neighbors"
    end
  end
end
