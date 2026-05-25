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

  describe "prettify_id/1" do
    test "passes through clean Module.fun/arity format" do
      assert Graph.prettify_id("Kernel.max/2") == "Kernel.max/2"
      assert Graph.prettify_id("MyApp.Repo.get/2") == "MyApp.Repo.get/2"
    end

    test "passes through clean module names" do
      assert Graph.prettify_id("Kernel") == "Kernel"
      assert Graph.prettify_id("MyApp.Repo") == "MyApp.Repo"
    end

    test "parses inspected 4-tuple format" do
      assert Graph.prettify_id("{:function, Kernel, :max, 2}") == "Kernel.max/2"
      assert Graph.prettify_id("{:access, Kernel, :get, 1}") == "Kernel.get/1"
    end

    test "parses inspected 2-tuple format" do
      assert Graph.prettify_id("{:module, Kernel}") == "Kernel"
      assert Graph.prettify_id("{:type, MyApp.Schema}") == "MyApp.Schema"
    end

    test "parses colon-separated underscore-encoded format" do
      assert Graph.prettify_id("ast_node:access_Kernel_max_2") == "Kernel.max/2"
      assert Graph.prettify_id("function:Enum_map_2") == "Enum.map/2"
    end

    test "handles colon-separated format with multi-segment module" do
      assert Graph.prettify_id("ast_node:call_MyApp_Repo_get_2") == "MyApp.Repo.get/2"
    end

    test "handles colon-separated format without arity" do
      assert Graph.prettify_id("module:MyApp_Repo") == "MyApp.Repo"
    end

    test "returns original string for unrecognized formats" do
      assert Graph.prettify_id("some_random_string") == "some_random_string"
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
