defmodule Rageg.EmbeddingsTest do
  use ExUnit.Case, async: true

  alias Rageg.Embeddings

  describe "fetch_scatter_data/1" do
    test "returns ok with list of points" do
      assert {:ok, points} = Embeddings.fetch_scatter_data()
      assert is_list(points)
    end
  end

  describe "search/2" do
    test "returns ok with list of IDs" do
      assert {:ok, ids} = Embeddings.search("nonexistent query")
      assert is_list(ids)
    end
  end

  describe "nearest_neighbors/2" do
    test "returns ok with empty list for nonexistent entity" do
      assert {:ok, []} = Embeddings.nearest_neighbors("NonExistent.func/0")
    end
  end

  describe "stats/0" do
    test "returns a map with total and dimensions" do
      stats = Embeddings.stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :total)
      assert Map.has_key?(stats, :dimensions)
    end
  end
end
