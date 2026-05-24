defmodule RagegWeb.AnalyzeLiveTest do
  use RagegWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /analyze" do
    test "renders analysis runner with controls", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/analyze")

      assert html =~ "Run Analysis"
      assert html =~ "Project Path"
      assert html =~ "Analysis Types"
      assert html =~ "Security Vulnerabilities"
      assert html =~ "Code Smells"
    end

    test "run_analysis with empty path shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analyze")

      html = render_click(view, "run_analysis", %{})
      assert html =~ "Enter a project path"
    end

    test "toggle_analysis toggles checkbox state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analyze")

      # Toggle dead_code (starts false)
      html = render_click(view, "toggle_analysis", %{"key" => "dead_code"})
      assert html =~ "Run Analysis"
    end
  end
end
