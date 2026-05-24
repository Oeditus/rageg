defmodule Rageg.QualityTest do
  use ExUnit.Case, async: true

  alias Rageg.Quality

  describe "tabs/0" do
    test "returns 6 tabs with name, label, icon" do
      tabs = Quality.tabs()

      assert [_, _, _, _, _, _] = tabs

      for {_key, label, icon} <- tabs do
        assert is_binary(label)
        assert String.starts_with?(icon, "hero-")
      end
    end
  end

  describe "summary/1" do
    test "returns a map with all quality dimension counts" do
      summary = Quality.summary("nonexistent_path")

      assert is_map(summary)
      assert Map.has_key?(summary, :smells)
      assert Map.has_key?(summary, :security)
      assert Map.has_key?(summary, :dead_code)
      assert Map.has_key?(summary, :duplication)
      assert Map.has_key?(summary, :complexity)
      assert Map.has_key?(summary, :business_logic)
    end

    test "returns zeros for nonexistent paths" do
      summary = Quality.summary("nonexistent_path")

      for {_key, count} <- summary do
        assert is_integer(count)
        assert count >= 0
      end
    end
  end

  describe "fetch_* functions" do
    test "fetch_smells returns ok tuple" do
      assert {:ok, list} = Quality.fetch_smells("nonexistent")
      assert is_list(list)
    end

    test "fetch_security returns ok tuple" do
      assert {:ok, list} = Quality.fetch_security("nonexistent")
      assert is_list(list)
    end

    test "fetch_dead_code returns ok tuple" do
      assert {:ok, list} = Quality.fetch_dead_code()
      assert is_list(list)
    end

    test "fetch_duplication returns ok tuple" do
      assert {:ok, list} = Quality.fetch_duplication("nonexistent")
      assert is_list(list)
    end

    test "fetch_complexity returns ok tuple" do
      assert {:ok, list} = Quality.fetch_complexity("nonexistent")
      assert is_list(list)
    end

    test "fetch_business_logic returns ok tuple" do
      assert {:ok, list} = Quality.fetch_business_logic("nonexistent")
      assert is_list(list)
    end
  end
end
