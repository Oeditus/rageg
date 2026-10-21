defmodule RagegWeb.ErrorHTMLTest do
  use RagegWeb.ConnCase, async: false

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders a styled 404 page" do
    html = render_to_string(RagegWeb.ErrorHTML, "404", "html", [])

    assert html =~ "404"
    assert html =~ "Page not found"
    assert html =~ "Back to the dashboard"
    assert html =~ ~s(href="/")
  end

  test "renders a styled 500 page" do
    html = render_to_string(RagegWeb.ErrorHTML, "500", "html", [])

    assert html =~ "500"
    assert html =~ "Something went wrong"
  end

  test "falls back to the status message for other codes" do
    html = render_to_string(RagegWeb.ErrorHTML, "403", "html", [])

    assert html =~ "403"
    assert html =~ "The request could not be completed."
  end

  test "escapes interpolated assigns" do
    html = render_to_string(RagegWeb.ErrorHTML, "404", "html", title: "<script>")

    refute html =~ "<script>"
  end
end
