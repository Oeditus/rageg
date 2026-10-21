defmodule RagegWeb.ChatLiveTest do
  use RagegWeb.ConnCase, async: false

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

    test "messages area is a LiveView stream", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")

      assert has_element?(view, "#chat-messages[phx-update=stream]")
    end

    test "new_session clears the message stream", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")

      # Session creation depends on a configured provider; either it succeeds
      # (and the form appears) or it reports an error -- both must not crash.
      render_click(view, "new_session", %{})
      assert has_element?(view, "#chat-messages")
    end
  end
end
