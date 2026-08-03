defmodule RagegWeb.MetacredoLiveTest do
  use RagegWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "GET /metacredo" do
    test "renders the MetaCredo analysis page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/metacredo")

      assert html =~ "MetaCredo Static Analysis"
      assert html =~ "Strict Mode"
      assert html =~ "Run Analysis"
    end

    test "has expected UI controls", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metacredo")

      assert has_element?(view, "#metacredo-strict-toggle")
      assert has_element?(view, "#metacredo-run-btn")
    end

    test "toggles strict mode on click", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metacredo")

      html = render_click(view, "toggle_strict", %{})
      assert html =~ "MetaCredo Static Analysis"
    end

    test "handles page changes gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metacredo")

      html = render_click(view, "change_page", %{"page" => "2"})
      assert html =~ "MetaCredo Static Analysis"
    end
  end
end
