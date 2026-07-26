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
    test "runs metacredo on valid directory" do
      # Analyze this repo's lib directory
      {:ok, result} = Metacredo.analyze("lib/rageg")

      assert is_integer(result.source_files_count)
      assert is_list(result.issues)
      assert is_map(result.summary)
      assert is_integer(result.timing_ms)
    end
  end
end
