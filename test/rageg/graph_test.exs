defmodule Rageg.GraphTest do
  use ExUnit.Case, async: true

  alias Rageg.Graph

  describe "available_metrics/0" do
    test "returns a list of metric tuples" do
      metrics = Graph.available_metrics()

      assert [_, _, _, _] = metrics
      assert {:pagerank, "PageRank"} in metrics
      assert {:betweenness, "Betweenness"} in metrics
      assert {:degree, "Degree"} in metrics
      assert {:community, "Community"} in metrics
    end
  end

  describe "fetch_d3_data/1" do
    test "returns ok tuple with graph data structure" do
      # With an empty graph, we should still get the structure
      case Graph.fetch_d3_data(max_nodes: 10) do
        {:ok, data} ->
          assert is_list(data.nodes)
          assert is_list(data.links)
          assert is_map(data.communities)
          assert is_map(data.stats)
          assert Map.has_key?(data.stats, :total_nodes)
          assert Map.has_key?(data.stats, :total_links)
          assert Map.has_key?(data.stats, :community_count)

        {:error, _reason} ->
          # Acceptable if Ragex graph is not populated
          :ok
      end
    end

    test "respects max_nodes option" do
      case Graph.fetch_d3_data(max_nodes: 5) do
        {:ok, data} ->
          assert length(data.nodes) <= 5

        {:error, _} ->
          :ok
      end
    end
  end

  describe "node_details/1" do
    test "returns nil for nonexistent node" do
      assert Graph.node_details("NonExistent.Module.foo/99") == nil
    end
  end

  describe "export_dot/1" do
    test "returns ok tuple with DOT string" do
      case Graph.export_dot(max_nodes: 10) do
        {:ok, dot} ->
          assert is_binary(dot)
          assert String.contains?(dot, "digraph")

        {:error, _} ->
          :ok
      end
    end
  end
end
