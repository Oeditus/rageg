defmodule RagegWeb.RefactorLiveTest do
  use RagegWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /refactor" do
    test "renders operation picker", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/refactor")

      assert html =~ "Refactoring"
      assert html =~ "Rename Function"
      assert html =~ "Rename Module"
      assert html =~ "Extract Function"
    end

    test "select_operation shows parameter form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/refactor")

      html = render_click(view, "select_operation", %{"op" => "rename_function"})
      assert html =~ "Module"
      assert html =~ "Current Name"
      assert html =~ "New Name"
      assert html =~ "Apply"
    end

    test "back_to_picker returns to operation grid", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/refactor")

      render_click(view, "select_operation", %{"op" => "rename_function"})
      html = render_click(view, "back_to_picker", %{})
      assert html =~ "Rename Function"
      assert html =~ "Rename Module"
    end
  end
end
