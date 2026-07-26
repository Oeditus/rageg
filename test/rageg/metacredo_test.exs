defmodule Rageg.MetacredoTest do
  use ExUnit.Case, async: true

  alias Rageg.Metacredo

  describe "categories/0" do
    test "returns list of atom categories" do
      cats = Metacredo.categories()
      assert is_list(cats)
      assert :refactor in cats
      assert :security in cats
    end
  end

  describe "analyze/2" do
    test "runs metacredo on valid directory and populates snippets and suggestions" do
      {:ok, result} = Metacredo.analyze("lib/rageg")

      assert is_integer(result.source_files_count)
      assert is_list(result.issues)
      assert is_map(result.summary)
      assert is_integer(result.timing_ms)

      if issue = Enum.find(result.issues, &(&1.snippet != nil)) do
        assert is_map(issue.snippet)
        assert is_list(issue.snippet.lines)
        assert Enum.any?(issue.snippet.lines, & &1.is_target)
      end

      for issue <- result.issues do
        assert is_binary(issue.suggestion)
        assert String.length(issue.suggestion) > 0
      end
    end

    test "persists and retrieves cached result" do
      path = "lib/rageg"
      {:ok, result} = Metacredo.analyze(path)

      cached = Metacredo.get_cached_result(path)
      assert cached != nil
      assert cached.source_files_count == result.source_files_count
      assert length(cached.issues) == length(result.issues)
    end
  end
end
