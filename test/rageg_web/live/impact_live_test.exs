defmodule RagegWeb.ImpactLiveTest do
  use RagegWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /impact" do
    test "renders impact analysis page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/impact")

      assert html =~ "Impact Analysis"
      assert html =~ "Target function or module"
      assert html =~ "Analyze"
    end

    test "analyze with empty target shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/impact")

      html = render_click(view, "analyze", %{})
      assert html =~ "Enter a target"
    end
  end
end
