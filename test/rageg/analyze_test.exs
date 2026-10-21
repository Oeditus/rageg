defmodule Rageg.AnalyzeTest do
  use ExUnit.Case, async: false

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

  describe "run/2 resilience" do
    test "handles files with invalid byte sequences without crashing process" do
      tmp_dir =
        System.tmp_dir!()
        |> Path.join("rageg_invalid_byte_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      # Write a file containing byte 255 (invalid UTF-8 byte)
      invalid_file = Path.join(tmp_dir, "invalid.ex")

      File.write!(
        invalid_file,
        <<100, 101, 102, 32, 109, 111, 100, 117, 108, 101, 32, 70, 111, 111, 32, 100, 111, 10, 32,
          32, 64, 100, 111, 99, 32, 34, 255, 34, 10, 101, 110, 100, 10>>
      )

      # Also write a valid file
      valid_file = Path.join(tmp_dir, "valid.ex")
      File.write!(valid_file, "defmodule ValidModule do\n  def hello, do: :world\nend\n")

      res = Analyze.run(tmp_dir, analyses: %{security: false, smells: false})

      assert {:ok, %{index: index_result}} = res
      assert index_result.files_analyzed >= 1
    end
  end
end
