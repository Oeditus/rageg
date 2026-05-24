defmodule RagegWeb.DependenciesLiveTest do
  use RagegWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /dependencies" do
    test "renders dependencies page with tabs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dependencies")

      assert html =~ "Dependencies"
      assert html =~ "Coupling"
      assert html =~ "Circular Deps"
      assert html =~ "God Modules"
      assert html =~ "Unused Modules"
    end

    test "switch_tab event changes active tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dependencies")

      html = render_click(view, "switch_tab", %{"tab" => "circular"})
      assert html =~ "tab-active"
    end

    test "handles empty graph gracefully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dependencies")

      # Should not crash even with no data
      assert html =~ "Dependencies"
    end
  end
end
