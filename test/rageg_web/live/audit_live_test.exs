defmodule RagegWeb.AuditLiveTest do
  use RagegWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /audit" do
    test "renders audit page with controls", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/audit")

      assert html =~ "Audit Report"
      assert html =~ "Project Path"
      assert html =~ "Run Audit"
      assert html =~ "Provider"
    end

    test "run_audit with empty path shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/audit")

      html = render_click(view, "run_audit", %{})
      assert html =~ "Enter a project path"
    end

    test "change_provider updates the selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/audit")

      html = render_click(view, "change_provider", %{"provider" => "openai"})
      assert html =~ "Audit Report"
    end
  end
end
