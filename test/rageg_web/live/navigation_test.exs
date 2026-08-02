defmodule RagegWeb.NavigationTest do
  use RagegWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

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
    test "dashboard renders all stat sections when active profile is set", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      # Dashboard content (sidebar is in the root layout, not LiveView HTML)
      assert html =~ "Dashboard"
      assert html =~ "Knowledge Graph"
      assert html =~ "AI Cache"
      assert html =~ "dllb Backend"
    end

    test "renders empty page with Select project when no profile is active", %{conn: conn} do
      Rageg.Profiles.clear_all!()
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Select project"
      assert html =~ "no-project-empty-state"
    end
  end
end
