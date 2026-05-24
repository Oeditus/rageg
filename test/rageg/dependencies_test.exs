defmodule Rageg.DependenciesTest do
  use ExUnit.Case, async: true

  alias Rageg.Dependencies

  describe "tabs/0" do
    test "returns 4 tabs" do
      tabs = Dependencies.tabs()

      assert [_, _, _, _] = tabs

      for {_key, label, icon} <- tabs do
        assert is_binary(label)
        assert String.starts_with?(icon, "hero-")
      end
    end
  end

  describe "summary/0" do
    test "returns a map with dependency counts" do
      summary = Dependencies.summary()

      assert is_map(summary)
      assert Map.has_key?(summary, :total_modules)
      assert Map.has_key?(summary, :circular_cycles)
      assert Map.has_key?(summary, :god_modules)
      assert Map.has_key?(summary, :unused_modules)
      assert Map.has_key?(summary, :unstable_modules)
    end
  end

  describe "fetch_* functions" do
    test "fetch_coupling returns ok tuple with list" do
      assert {:ok, list} = Dependencies.fetch_coupling()
      assert is_list(list)
    end

    test "fetch_circular_deps returns ok tuple with list" do
      assert {:ok, list} = Dependencies.fetch_circular_deps()
      assert is_list(list)
    end

    test "fetch_god_modules returns ok tuple with list" do
      assert {:ok, list} = Dependencies.fetch_god_modules()
      assert is_list(list)
    end

    test "fetch_unused_modules returns ok tuple with list" do
      assert {:ok, list} = Dependencies.fetch_unused_modules()
      assert is_list(list)
    end
  end
end
