defmodule RagegWeb.NavigationTest do
  use RagegWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @placeholder_routes [
    {"/embeddings", "Embedding Space"},
    {"/analyze", "Run Analysis"}
  ]

  describe "placeholder pages" do
    for {path, title} <- @placeholder_routes do
      test "#{path} renders #{title}", %{conn: conn} do
        {:ok, _view, html} = live(conn, unquote(path))

        assert html =~ unquote(title)
        assert html =~ "Phase"
      end
    end
  end

  describe "dllb pages" do
    test "/dllb renders overview with sub-page cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dllb")

      assert html =~ "dllb Backend Explorer"
      assert html =~ "Supervision Tree"
      assert html =~ "Storage Engine"
      assert html =~ "HNSW Vectors"
    end

    test "/dllb/actors renders actors placeholder", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dllb/actors")

      assert html =~ "Supervision Tree"
    end
  end

  describe "sidebar navigation" do
    test "dashboard renders all stat sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      # Dashboard content (sidebar is in the root layout, not LiveView HTML)
      assert html =~ "Dashboard"
      assert html =~ "Knowledge Graph"
      assert html =~ "AI Cache"
      assert html =~ "dllb Backend"
    end
  end
end
