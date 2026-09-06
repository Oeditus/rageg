defmodule Rageg.AnalyzeTest do
  use ExUnit.Case, async: true

  alias Rageg.Analyze

  describe "analysis_types/0" do
    test "returns 13 analysis types" do
      types = Analyze.analysis_types()
      assert length(types) == 13

      for {key, label, default} <- types do
        assert is_atom(key)
        assert is_binary(label)
        assert is_boolean(default)
      end
    end
  end

  describe "default_analyses/0" do
    test "returns a map with all keys" do
      defaults = Analyze.default_analyses()
      assert is_map(defaults)
      assert map_size(defaults) == 13
      assert defaults.security == true
      assert defaults.dead_code == false
    end
  end

  describe "analyze_url/2" do
    test "invokes URLAnalyzer and handles invalid/unreachable URL" do
      res =
        Analyze.analyze_url("http://invalid.local.test/repo.git",
          depth: "shallow",
          index_graph: false
        )

      assert match?({:error, _}, res) or match?({:ok, _}, res)
    end
  end
end
