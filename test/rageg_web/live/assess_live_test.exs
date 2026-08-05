defmodule RagegWeb.AssessLiveTest do
  use RagegWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Rageg.Profiles

  setup do
    Profiles.clear_all!()
    {:ok, profile} = Profiles.create(File.cwd!())
    Profiles.switch(profile.id)
    on_exit(fn -> Profiles.clear_all!() end)
    :ok
  end

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

    test "allows form change and branch assessment submission", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/assess")

      view
      |> form("#assess-form", %{
        "base" => "main",
        "head" => "main",
        "format" => "markdown"
      })
      |> render_change()

      html =
        view
        |> form("#assess-form", %{
          "base" => "main",
          "head" => "main",
          "format" => "markdown"
        })
        |> render_submit()

      assert html =~ "Assessing..." or html =~ "Assessment Progress" or
               html =~ "Assessment Summary" or html =~ "No files changed"
    end

    test "refresh_branches button triggers branch reload", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/assess")

      assert view
             |> element("button[phx-click='refresh_branches']")
             |> render_click() =~ "Head Branch"
    end
  end
end
