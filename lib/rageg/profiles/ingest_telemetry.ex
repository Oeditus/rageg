defmodule Rageg.Profiles.IngestTelemetry do
  @moduledoc """
  Telemetry instrumentation for the dllb ingestion pipeline.

  Emits standard `:telemetry.span/3` events for every pipeline phase
  and attaches `Logger`-based handlers so timings are visible without
  an external metrics backend.

  ## Event prefix

      [:rageg, :ingest, <phase>]

  Each phase emits the usual `start / stop / exception` triplet.

  ## Phases

  | Event suffix   | Metadata                                |
  |----------------|-----------------------------------------|
  | `:bootstrap`   | (none)                                  |
  | `:discovery`   | `%{path: ..., file_count: ...}`         |
  | `:file`        | `%{path: ..., language: ...}`           |
  | `:file_parse`  | `%{path: ..., language: ...}`           |
  | `:querygen`    | `%{path: ..., creates: N, relates: N}`  |
  | `:batch_nodes` | `%{path: ..., count: N}`                |
  | `:batch_edges` | `%{path: ..., count: N}`                |
  | `:save_stats`  | `%{project_tag: ...}`                   |
  | `:total`       | `%{project_tag: ..., file_count: ...}`  |
  """

  require Logger

  # -- Public --

  @doc "Attaches all Logger-backed telemetry handlers. Idempotent."
  @spec attach() :: :ok
  def attach do
    handlers()
    |> Enum.each(fn {id, event, fun} ->
      # detach first to make re-attaching safe (e.g. in tests)
      :telemetry.detach(id)
      :telemetry.attach(id, event, fun, nil)
    end)

    :ok
  end

  # -- Span helpers (called by DllbIngestor) --

  @doc "Wraps `fun` in a `:telemetry.span` for the given phase."
  @spec span(atom(), map(), (-> result)) :: result when result: var
  def span(phase, metadata, fun) when is_atom(phase) and is_map(metadata) do
    :telemetry.span([:rageg, :ingest, phase], metadata, fn ->
      result = fun.()
      {result, metadata}
    end)
  end

  @doc "Like `span/3` but lets the function return `{result, extra_metadata}` to enrich the stop event."
  @spec span_with_meta(atom(), map(), (-> {result, map()})) :: result when result: var
  def span_with_meta(phase, metadata, fun) when is_atom(phase) and is_map(metadata) do
    :telemetry.span([:rageg, :ingest, phase], metadata, fun)
  end

  # -- Private: handler definitions --

  defp handlers do
    phases = [
      :bootstrap,
      :discovery,
      :file,
      :file_parse,
      :querygen,
      :batch_nodes,
      :batch_edges,
      :save_stats,
      :total
    ]

    Enum.flat_map(phases, fn phase ->
      stop_id = "rageg.ingest.#{phase}.stop"
      stop_event = [:rageg, :ingest, phase, :stop]

      exception_id = "rageg.ingest.#{phase}.exception"
      exception_event = [:rageg, :ingest, phase, :exception]

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

    Logger.info("[ingest:#{phase}] #{duration_ms}ms#{extra}")
  end

  @doc false
  def handle_exception(event, measurements, metadata, _config) do
    phase = event |> Enum.at(2) |> Atom.to_string()
    duration_ms = div(measurements.duration, 1_000_000)
    kind = metadata[:kind]
    reason = metadata[:reason]

    Logger.error("[ingest:#{phase}] FAILED after #{duration_ms}ms -- #{kind}: #{inspect(reason)}")
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
