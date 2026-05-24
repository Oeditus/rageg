defmodule RagegWeb.QualityLiveTest do
  use RagegWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /quality" do
    test "renders quality page with tabs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/quality")

      assert html =~ "Code Quality"
      assert html =~ "Code Smells"
      assert html =~ "Security"
      assert html =~ "Dead Code"
      assert html =~ "Duplication"
      assert html =~ "Complexity"
      assert html =~ "Business Logic"
    end

    test "switch_tab event changes active tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/quality")

      html = render_click(view, "switch_tab", %{"tab" => "security"})
      assert html =~ "tab-active"
    end

    test "handles empty analysis results gracefully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/quality")

      # Should not crash even with no analysis data
      assert html =~ "Code Quality"
    end
  end
end
