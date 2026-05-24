defmodule Rageg.ChatTest do
  use ExUnit.Case, async: true

  alias Rageg.Chat

  describe "providers/0" do
    test "returns 4 providers" do
      providers = Chat.providers()

      assert [_, _, _, _] = providers
      assert {:deepseek_r1, "DeepSeek R1"} in providers
      assert {:openai, "OpenAI"} in providers
      assert {:anthropic, "Anthropic"} in providers
      assert {:ollama, "Ollama"} in providers
    end
  end

  describe "session_active?/1" do
    test "returns false for nonexistent session" do
      refute Chat.session_active?("nonexistent-session-id")
    end
  end

  describe "get_messages/1" do
    test "returns empty list for nonexistent session" do
      assert {:ok, []} = Chat.get_messages("nonexistent-session-id")
    end
  end

  describe "end_session/1" do
    test "does not crash for nonexistent session" do
      assert :ok = Chat.end_session("nonexistent-session-id")
    end
  end
end
