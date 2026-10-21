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

  describe "project_2d/1" do
    test "returns one coordinate pair per input vector" do
      points = Embeddings.project_2d([[1.0, 0.0], [0.0, 1.0], [1.0, 1.0]])

      assert length(points) == 3
      assert Enum.all?(points, fn {x, y} -> is_float(x) and is_float(y) end)
    end

    test "centres the projection on the mean" do
      points = Embeddings.project_2d([[1.0, 0.0], [0.0, 1.0], [-1.0, 0.0], [0.0, -1.0]])

      {sum_x, sum_y} =
        Enum.reduce(points, {0.0, 0.0}, fn {x, y}, {ax, ay} -> {ax + x, ay + y} end)

      assert_in_delta sum_x, 0.0, 0.001
      assert_in_delta sum_y, 0.0, 0.001
    end

    test "preserves relative distances along the dominant axis" do
      # Three collinear points: the first principal component must be the line
      # they lie on, so the first coordinate is monotonic in the input.
      points = Embeddings.project_2d([[0.0, 0.0], [1.0, 1.0], [3.0, 3.0]])
      xs = Enum.map(points, fn {x, _y} -> x end)

      assert xs == Enum.sort(xs) or xs == Enum.reverse(Enum.sort(xs))
      assert Enum.uniq(xs) |> length() == 3
    end

    test "handles a single vector" do
      assert Embeddings.project_2d([[1.0, 2.0, 3.0]]) == [{0.0, 0.0}]
    end

    test "handles identical vectors without crashing" do
      points = Embeddings.project_2d([[1.0, 2.0], [1.0, 2.0]])
      assert length(points) == 2
    end

    test "handles an empty list" do
      assert Embeddings.project_2d([]) == []
    end
  end
end
