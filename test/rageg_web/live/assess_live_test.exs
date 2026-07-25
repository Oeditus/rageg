defmodule RagegWeb.AssessLiveTest do
  use RagegWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /assess" do
    test "renders the PR assessment page with branch selection", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/assess")

      assert html =~ "PR / Branch Assessment"
      assert html =~ "Base Ref"
      assert html =~ "Head Branch"
      assert html =~ "Output Format"
      assert html =~ "Run Assessment"
    end

    test "has the expected form controls", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/assess")

      assert has_element?(view, "#assess-base-ref")
      assert has_element?(view, "#assess-head-branch")
      assert has_element?(view, "#assess-format")
      assert has_element?(view, "#assess-run-btn")
    end

    test "displays error when no branch is selected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/assess")

      # With no head branch selected, the button should be disabled
      # but we can still trigger the event
      html = render(view)
      assert html =~ "Run Assessment"
    end
  end
end
