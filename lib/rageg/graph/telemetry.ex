defmodule Rageg.Graph.Telemetry do
  @moduledoc """
  Telemetry instrumentation for the knowledge-graph pipeline.

  Attaches `Logger`-based handlers to the `:telemetry.span/3` events
  emitted by `Ragex.Graph.Algorithms` so timings are visible without
  an external metrics backend.

  ## Event prefix

      [:ragex, :graph, <phase>]

  Each phase emits the usual `start / stop / exception` triplet.

  ## Phases

  | Event suffix           | Metadata                          |
  |------------------------|-----------------------------------|
  | `:get_call_edges`      | `%{edge_count: N}`                |
  | `:build_all_nodes`     | `%{node_count: N}`                |
  | `:pagerank`            | `%{node_count: N, iterations: N}` |
  | `:degree_centrality`   | `%{node_count: N}`                |
  | `:detect_communities`  | `%{community_count: N}`           |
  | `:build_nodes`         | `%{count: N}`                     |
  | `:build_links`         | `%{count: N}`                     |
  """

  require Logger

  @phases [
    :get_call_edges,
    :build_all_nodes,
    :pagerank,
    :degree_centrality,
    :detect_communities,
    :build_nodes,
    :build_links
  ]

  @doc "Attaches all Logger-backed telemetry handlers. Idempotent."
  @spec attach() :: :ok
  def attach do
    handlers()
    |> Enum.each(fn {id, event, fun} ->
      :telemetry.detach(id)
      :telemetry.attach(id, event, fun, nil)
    end)

    :ok
  end

  # -- Private: handler definitions --

  defp handlers do
    Enum.flat_map(@phases, fn phase ->
      stop_id = "ragex.graph.#{phase}.stop"
      stop_event = [:ragex, :graph, phase, :stop]

      exception_id = "ragex.graph.#{phase}.exception"
      exception_event = [:ragex, :graph, phase, :exception]

      [
        {stop_id, stop_event, &__MODULE__.handle_stop/4},
        {exception_id, exception_event, &__MODULE__.handle_exception/4}
      ]
    end)
  end

  @doc false
  def handle_stop(event, measurements, metadata, _config) do
    phase = event |> Enum.at(2) |> Atom.to_string()
    duration_ms = div(measurements.duration, 1_000_000)
    extra = format_meta(metadata)

    Logger.info("[graph:#{phase}] #{duration_ms}ms#{extra}")
  end

  @doc false
  def handle_exception(event, measurements, metadata, _config) do
    phase = event |> Enum.at(2) |> Atom.to_string()
    duration_ms = div(measurements.duration, 1_000_000)
    kind = metadata[:kind]
    reason = metadata[:reason]

    Logger.error("[graph:#{phase}] FAILED after #{duration_ms}ms -- #{kind}: #{inspect(reason)}")
  end

  defp format_meta(meta) when map_size(meta) == 0, do: ""

  defp format_meta(meta) do
    parts =
      meta
      |> Enum.reject(fn {k, _} -> k in [:telemetry_span_context, :kind, :reason, :stacktrace] end)
      |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end)

    case parts do
      [] -> ""
      _ -> " " <> Enum.join(parts, " ")
    end
  end
end
