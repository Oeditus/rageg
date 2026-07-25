defmodule RagegWeb.ConfigurationLiveTest do
  use RagegWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Rageg.AIKeys

  @config_file "~/.rageg/.ai_keys.json"

  setup do
    # Backup existing config if any
    path = Path.expand(@config_file)
    backup_path = path <> ".backup"

    if File.exists?(path) do
      File.rename!(path, backup_path)
    end

    on_exit(fn ->
      if File.exists?(backup_path) do
        if File.exists?(path), do: File.rm!(path)
        File.rename!(backup_path, path)
      else
        if File.exists?(path), do: File.rm!(path)
      end

      # Reload keys to restore environment
      AIKeys.load_keys()
    end)

    :ok
  end

  describe "GET /configuration" do
    test "renders the configuration page with active provider fields", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/configuration")

      assert html =~ "Configuration"
      assert html =~ "DeepSeek R1 API Key"
      assert html =~ "OpenAI API Key"
      assert html =~ "Anthropic API Key"
      assert html =~ "Default AI Provider"
      assert html =~ "Automatic Provider Fallback"
    end

    test "submits and saves configuration changes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/configuration")

      html =
        view
        |> form("#config-form", %{
          config: %{
            deepseek_r1: "test-deepseek-key",
            openai: "test-openai-key",
            anthropic: "test-anthropic-key",
            default_provider: "openai",
            fallback_enabled: "true"
          }
        })
        |> render_submit()

      assert html =~ "Configuration saved successfully!"

      # Check keys persisted in the AIKeys configuration
      config = AIKeys.get_config()
      assert config.deepseek_r1 == "test-deepseek-key"
      assert config.openai == "test-openai-key"
      assert config.anthropic == "test-anthropic-key"
      assert config.default_provider == :openai
      assert config.fallback_enabled == true
    end
  end
end
