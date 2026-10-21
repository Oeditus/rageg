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

    test "search input is wired to send typed values", %{conn: conn} do
      path = Rageg.Profiles.active().path

      cache_file =
        Path.expand(
          Path.join(
            "~/.rageg/.metacredo_cache",
            "#{:crypto.hash(:sha256, path) |> Base.encode16(case: :lower)}.json"
          )
        )

      on_exit(fn -> File.rm(cache_file) end)

      # Seed a cached result so the results section (which contains the search
      # input) is rendered on mount.
      Rageg.Metacredo.save_cached_result(path, %{
        source_files_count: 0,
        issues: [],
        summary: %{total: 0, by_category: %{}, by_severity: %{}, by_check: %{}},
        timing_ms: 0
      })

      {:ok, view, _html} = live(conn, ~p"/metacredo")
      assert has_element?(view, ~s|#metacredo-search-input[name="query"]|)
    end

    test "handles page changes gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metacredo")

      html = render_click(view, "change_page", %{"page" => "2"})
      assert html =~ "MetaCredo Static Analysis"
    end
  end
end
