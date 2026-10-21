defmodule RagegWeb.RefactorLiveTest do
  use RagegWeb.ConnCase, async: false

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

  describe "preview -> confirm -> apply workflow" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/refactor")
      render_click(view, "select_operation", %{"op" => "rename_function"})
      {:ok, view: view}
    end

    test "apply is disabled until a preview exists", %{view: view} do
      assert has_element?(view, "#refactor-apply-btn[disabled]")
      refute has_element?(view, "#refactor-confirm-overlay")
    end

    test "request_apply without a preview reports an error", %{view: view} do
      html = render_click(view, "request_apply", %{})

      assert html =~ "Generate a preview before applying"
      refute has_element?(view, "#refactor-confirm-overlay")
    end

    test "confirming requires an explicit second click", %{view: view} do
      # Simulate a clean preview result without touching the filesystem.
      send(
        view.pid,
        {:task_result, :refactor_preview,
         {:ok,
          %{
            diffs: [%{file: "lib/demo.ex", additions: 2, deletions: 1, html: "<div/>"}],
            conflicts: %{has_conflicts: false, conflicts: [], stats: %{errors: 0, warnings: 0}}
          }}}
      )

      html = render(view)
      assert html =~ "Refactoring Simulation Preview"
      refute has_element?(view, "#refactor-confirm-overlay")

      html = render_click(view, "request_apply", %{})
      assert html =~ "Apply this refactoring?"
      assert has_element?(view, "#refactor-confirm-run")

      html = render_click(view, "cancel_apply", %{})
      refute html =~ "Apply this refactoring?"
    end

    test "blocking conflicts prevent the confirmation step", %{view: view} do
      send(
        view.pid,
        {:task_result, :refactor_preview,
         {:ok,
          %{
            diffs: [],
            conflicts: %{
              has_conflicts: true,
              conflicts: [
                %{severity: :error, message: "name clash", file: nil, line: nil, suggestion: nil}
              ],
              stats: %{errors: 1, warnings: 0}
            }
          }}}
      )

      html = render_click(view, "request_apply", %{})
      assert html =~ "blocking conflict"
      refute has_element?(view, "#refactor-confirm-overlay")
    end
  end
end
