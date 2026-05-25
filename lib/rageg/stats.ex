defmodule Rageg.Stats do
  @moduledoc """
  Periodic statistics collector for Ragex and dllb.

  Polls Ragex graph stats, embedding stats, AI cache/usage stats,
  and dllb connection health at a configurable interval (default: 3s).
  Broadcasts snapshots on the `"stats"` PubSub topic so LiveViews
  can subscribe and update in real time.

  ## PubSub Topic

      Rageg.Stats.topic()  #=> "stats"

  ## Message Format

  Subscribers receive `{:stats_updated, snapshot}` where `snapshot`
  is a `t:snapshot/0` map.

  ## Usage

      # In a LiveView mount:
      Phoenix.PubSub.subscribe(Rageg.PubSub, Rageg.Stats.topic())
      stats = Rageg.Stats.current()

      # Handle updates:
      def handle_info({:stats_updated, stats}, socket) do
        {:noreply, assign(socket, stats: stats)}
      end
  """

  use GenServer

  @topic "stats"
  @default_interval 3_000

  @type snapshot :: %{
          graph: map(),
          embeddings: map(),
          cache: map(),
          ai_usage: map(),
          dllb: map(),
          fetched_at: DateTime.t()
        }

  # -- Client API --

  @doc """
  Starts the stats collector, linked to the caller.

  ## Options

    * `:interval` - polling interval in milliseconds (default: #{@default_interval})
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the PubSub topic for stats broadcasts.
  """
  @spec topic :: String.t()
  def topic, do: @topic

  @doc """
  Returns the latest cached snapshot synchronously.

  Falls back to `empty_snapshot/0` if the collector has not
  produced a snapshot yet.
  """
  @spec current :: snapshot()
  def current do
    GenServer.call(__MODULE__, :current)
  catch
    :exit, _ -> empty_snapshot()
  end

  @doc """
  Returns a snapshot with all fields set to empty/zero values.
  """
  @spec empty_snapshot :: snapshot()
  def empty_snapshot do
    %{
      graph: %{nodes: 0, edges: 0, density: 0.0, components: 0},
      embeddings: %{model: "n/a", dimensions: 0, total: 0},
      cache: %{hit_rate: 0.0, misses: 0, evictions: 0, size: 0},
      ai_usage: %{total_requests: 0, total_tokens: 0, estimated_cost: 0.0},
      dllb: %{connected: false, pool_size: 0, latency_ms: 0, nodes: 0, edges: 0, projects: 0},
      fetched_at: DateTime.utc_now()
    }
  end

  # -- Server callbacks --

  @impl GenServer
  def init(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)
    state = %{interval: interval, snapshot: empty_snapshot()}

    # First fetch after a short delay to let dependencies boot
    Process.send_after(self(), :poll, 500)

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:current, _from, state) do
    {:reply, state.snapshot, state}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    snapshot = fetch_all()
    Phoenix.PubSub.broadcast(Rageg.PubSub, @topic, {:stats_updated, snapshot})
    Process.send_after(self(), :poll, state.interval)
    {:noreply, %{state | snapshot: snapshot}}
  end

  # -- Private --

  defp fetch_all do
    %{
      graph: fetch_graph_stats(),
      embeddings: fetch_embedding_stats(),
      cache: fetch_cache_stats(),
      ai_usage: fetch_ai_usage(),
      dllb: fetch_dllb_health(),
      fetched_at: DateTime.utc_now()
    }
  end

  defp fetch_graph_stats do
    # Use persisted ingestion stats directly -- the live `Ragex.stats()` path
    # runs SELECT id, kind FROM ast_node which returns ~100K rows as a single
    # JSON line, overflowing the TCP line-packet buffer and corrupting the
    # connection pool.
    ingested = Rageg.Dllb.aggregate_ingest_stats()

    %{
      nodes: ingested.nodes,
      edges: ingested.edges,
      density: 0.0,
      components: 0
    }
  rescue
    _ -> %{nodes: 0, edges: 0, density: 0.0, components: 0}
  end

  defp fetch_embedding_stats do
    vs_stats =
      case Ragex.VectorStore.stats() do
        s when is_map(s) -> s
        _ -> %{}
      end

    # Model name comes from Bumblebee, not VectorStore
    model_name =
      case Ragex.Embeddings.Bumblebee.model_info() do
        %{name: name} -> name
        _ -> "n/a"
      end

    %{
      model: model_name,
      dimensions: Map.get(vs_stats, :dimensions, 0),
      total: Map.get(vs_stats, :total_embeddings, 0)
    }
  rescue
    _ -> %{model: "n/a", dimensions: 0, total: 0}
  end

  defp fetch_cache_stats do
    case Ragex.AI.Cache.stats() do
      stats when is_map(stats) ->
        hits = Map.get(stats, :hits, 0)
        misses = Map.get(stats, :misses, 0)
        total = hits + misses

        %{
          hit_rate: if(total > 0, do: hits / total, else: 0.0),
          misses: misses,
          evictions: Map.get(stats, :evictions, 0),
          size: Map.get(stats, :size, 0)
        }

      _ ->
        %{hit_rate: 0.0, misses: 0, evictions: 0, size: 0}
    end
  rescue
    _ -> %{hit_rate: 0.0, misses: 0, evictions: 0, size: 0}
  end

  defp fetch_ai_usage do
    case Ragex.AI.Usage.get_stats(:all) do
      stats when is_map(stats) ->
        %{
          total_requests: Map.get(stats, :total_requests, 0),
          total_tokens: Map.get(stats, :total_tokens, 0),
          estimated_cost: Map.get(stats, :estimated_cost, 0.0)
        }

      _ ->
        %{total_requests: 0, total_tokens: 0, estimated_cost: 0.0}
    end
  rescue
    _ -> %{total_requests: 0, total_tokens: 0, estimated_cost: 0.0}
  end

  defp fetch_dllb_health do
    connected = dllb_available?()
    ingested = Rageg.Dllb.aggregate_ingest_stats()

    %{
      connected: connected,
      pool_size: Application.get_env(:dllb, :pool_size, 0),
      latency_ms: if(connected, do: measure_dllb_latency(), else: 0),
      nodes: ingested.nodes,
      edges: ingested.edges,
      projects: ingested.projects
    }
  rescue
    _ -> %{connected: false, pool_size: 0, latency_ms: 0, nodes: 0, edges: 0, projects: 0}
  end

  defp dllb_available? do
    Application.get_env(:dllb, :enabled, false) &&
      match?({:ok, %Dllb.Result.Rows{}}, Dllb.query("SELECT * FROM _dllb_ping_"))
  rescue
    _ -> false
  end

  defp measure_dllb_latency do
    {microseconds, _} = :timer.tc(fn -> Dllb.query("SELECT * FROM _dllb_ping_") end)
    div(microseconds, 1_000)
  rescue
    _ -> 0
  end
end
