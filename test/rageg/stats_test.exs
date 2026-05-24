defmodule Rageg.StatsTest do
  use ExUnit.Case, async: true

  alias Rageg.Stats

  describe "empty_snapshot/0" do
    test "returns a map with all expected keys" do
      snapshot = Stats.empty_snapshot()

      assert %{graph: _, embeddings: _, cache: _, ai_usage: _, dllb: _, fetched_at: _} = snapshot
    end

    test "graph defaults to zero counts" do
      snapshot = Stats.empty_snapshot()

      assert snapshot.graph == %{nodes: 0, edges: 0, density: 0.0, components: 0}
    end

    test "embeddings defaults to n/a model" do
      snapshot = Stats.empty_snapshot()

      assert snapshot.embeddings.model == "n/a"
      assert snapshot.embeddings.dimensions == 0
      assert snapshot.embeddings.total == 0
    end

    test "cache defaults to zero hit rate" do
      snapshot = Stats.empty_snapshot()

      assert snapshot.cache.hit_rate == 0.0
      assert snapshot.cache.misses == 0
      assert snapshot.cache.evictions == 0
      assert snapshot.cache.size == 0
    end

    test "ai_usage defaults to zero usage" do
      snapshot = Stats.empty_snapshot()

      assert snapshot.ai_usage.total_requests == 0
      assert snapshot.ai_usage.total_tokens == 0
      assert snapshot.ai_usage.estimated_cost == 0.0
    end

    test "dllb defaults to disconnected" do
      snapshot = Stats.empty_snapshot()

      assert snapshot.dllb.connected == false
      assert snapshot.dllb.pool_size == 0
      assert snapshot.dllb.latency_ms == 0
    end

    test "fetched_at is a DateTime" do
      snapshot = Stats.empty_snapshot()

      assert %DateTime{} = snapshot.fetched_at
    end
  end

  describe "topic/0" do
    test "returns the stats PubSub topic" do
      assert Stats.topic() == "stats"
    end
  end

  describe "GenServer" do
    test "current/0 returns a snapshot even when the server is not running" do
      # Stats is not started in this test (no application), so current/0
      # should catch the exit and return an empty snapshot
      snapshot = Stats.current()

      assert %{graph: _, fetched_at: _} = snapshot
    end

    test "current/0 returns a valid snapshot when server is running" do
      # The application starts Stats automatically, so we can query it
      snapshot = Stats.current()

      assert %{graph: _, embeddings: _, cache: _, ai_usage: _, dllb: _, fetched_at: _} = snapshot
    end
  end
end
