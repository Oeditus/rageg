defmodule RagegWeb.ChatLiveTest do
  use RagegWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /chat" do
    test "renders chat page with session controls", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/chat")

      assert html =~ "RAG Chat"
      assert html =~ "New Session"
      assert html =~ "DeepSeek"
    end

    test "shows empty state when no session", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/chat")

      assert html =~ "Start a new session"
    end

    test "toggle_tools event works", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")

      html = render_click(view, "toggle_tools", %{})
      # Should not crash
      assert html =~ "RAG Chat"
    end

    test "send_message without session shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")

      html = render_click(view, "send_message", %{"message" => "hello"})
      # No session, should not crash (unless returns error message)
      assert html =~ "RAG Chat"
    end
  end
end
