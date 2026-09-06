defmodule Rageg.PluginsTest do
  use ExUnit.Case, async: true

  alias Rageg.Plugins

  describe "list_plugins/0" do
    test "returns topological list of registered plugins" do
      plugins = Plugins.list_plugins()
      assert is_list(plugins)

      if plugins != [] do
        plugin = List.first(plugins)
        assert Map.has_key?(plugin, :id)
        assert Map.has_key?(plugin, :name)
        assert Map.has_key?(plugin, :priority)
      end
    end
  end

  describe "list_plugin_tools/0" do
    test "returns list of aggregated tool schemas" do
      tools = Plugins.list_plugin_tools()
      assert is_list(tools)
    end
  end

  describe "list_running_tools/0" do
    test "returns active running tool calls list" do
      running = Plugins.list_running_tools()
      assert is_list(running) or is_map(running)
    end
  end

  describe "enable_plugin/1 and disable_plugin/1" do
    test "handles plugin toggling safely" do
      plugins = Plugins.list_plugins()

      if plugins != [] do
        first = List.first(plugins)
        assert :ok = Plugins.disable_plugin(first.id)
        assert :ok = Plugins.enable_plugin(first.id)
      end
    end
  end
end
