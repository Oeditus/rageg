defmodule Rageg.Profiles.DllbIngestor do
  @moduledoc """
  Ingests source files into the dllb database as MetaAST nodes and edges.

  Mirrors the pipeline from `Mix.Tasks.Dllb.Ingest` but is callable
  as a regular function with progress callbacks. Uses
  `Dllb.MetaAST.ingest_tree_queries/2` to generate queries and
  `Dllb.batch/1` to execute them efficiently.

  Every pipeline phase is instrumented via `:telemetry.span/3` through
  `Rageg.Profiles.IngestTelemetry`. Unchanged files (same mtime + size)
  are skipped automatically via `Rageg.Profiles.IngestCache`.
  """

  require Logger

  alias Dllb.MetaAST
  alias Rageg.Profiles.{FileDiscovery, IngestCache, IngestTelemetry}

  @batch_size 100

  @type ingest_result :: %{
          files_ok: non_neg_integer(),
          files_err: non_neg_integer(),
          files_cached: non_neg_integer(),
          nodes: non_neg_integer(),
          edges: non_neg_integer()
        }

  @type progress_fn :: (String.t() -> :ok)

  @doc """
  Bootstraps the dllb schema (idempotent) and ingests **changed** source
  files under the given path.

  Files whose mtime and size match the cached manifest are skipped.
  Pass `force: true` to bypass the cache entirely.

  ## Options

    * `:project_tag` - value for the `project_path` field (required)
    * `:on_progress` - `(String.t() -> :ok)` callback for status messages
    * `:batch_size` - queries per batch (default: #{@batch_size})
    * `:force` - when `true`, ignores the cache and re-ingests everything

  ## Returns

  `{:ok, ingest_result}` or `{:error, reason}`
  """
  @spec ingest(String.t(), keyword()) :: {:ok, ingest_result()} | {:error, term()}
  def ingest(path, opts \\ []) do
    project_tag = Keyword.fetch!(opts, :project_tag)
    on_progress = Keyword.get(opts, :on_progress, fn _ -> :ok end)
    batch_size = Keyword.get(opts, :batch_size, @batch_size)
    force? = Keyword.get(opts, :force, false)

    IngestTelemetry.span_with_meta(
      :total,
      %{project_tag: project_tag, path: path},
      fn ->
        result = do_ingest(path, project_tag, on_progress, batch_size, force?)
        {result, %{project_tag: project_tag, path: path}}
      end
    )
  rescue
    e -> {:error, Exception.message(e)}
  end

  # -- Private --

  defp do_ingest(path, project_tag, on_progress, batch_size, force?) do
    on_progress.("Bootstrapping dllb schema...")

    IngestTelemetry.span(:bootstrap, %{}, fn ->
      bootstrap_schema!()
    end)

    all_files =
      IngestTelemetry.span_with_meta(:discovery, %{path: path}, fn ->
        files = FileDiscovery.discover(path)
        {files, %{path: path, file_count: length(files)}}
      end)

    total_discovered = length(all_files)
    on_progress.("Discovered #{total_discovered} source files")

    # --- Cache filtering ---
    {files, cached_count} =
      if force? do
        {all_files, 0}
      else
        IngestCache.stale(project_tag, all_files)
      end

    stale_count = length(files)

    if cached_count > 0 do
      on_progress.("Cache hit: #{cached_count} unchanged, #{stale_count} to ingest")
    end

    if stale_count == 0 do
      on_progress.("All #{total_discovered} files unchanged -- nothing to ingest")
      {:ok, %{files_ok: 0, files_err: 0, files_cached: cached_count, nodes: 0, edges: 0}}
    else
      result = ingest_files(files, stale_count, project_tag, batch_size, on_progress)

      IngestTelemetry.span(:save_stats, %{project_tag: project_tag}, fn ->
        Rageg.Dllb.save_ingest_stats(project_tag, result)
      end)

      # Update cache with the full file set (including unchanged ones)
      IngestCache.update(project_tag, all_files)

      result = Map.put(result, :files_cached, cached_count)

      on_progress.(
        "Done: #{result.files_ok} ingested, #{cached_count} cached, " <>
          "#{result.nodes} nodes, #{result.edges} edges"
      )

      {:ok, result}
    end
  end

  defp ingest_files(files, total, project_tag, batch_size, on_progress) do
    files
    |> Enum.with_index(1)
    |> Enum.reduce(
      %{files_ok: 0, files_err: 0, nodes: 0, edges: 0},
      fn {{file_path, lang}, idx}, acc ->
        on_progress.("Ingesting [#{idx}/#{total}] #{Path.relative_to_cwd(file_path)}")

        outcome =
          IngestTelemetry.span(:file, %{path: file_path, language: lang}, fn ->
            ingest_one(file_path, lang, project_tag, batch_size)
          end)

        case outcome do
          {:ok, nodes, edges} ->
            %{
              acc
              | files_ok: acc.files_ok + 1,
                nodes: acc.nodes + nodes,
                edges: acc.edges + edges
            }

          {:error, reason} ->
            Logger.warning("Ingest failed for #{file_path}: #{inspect(reason)}")
            %{acc | files_err: acc.files_err + 1}
        end
      end
    )
  end

  defp bootstrap_schema! do
    case Dllb.Schema.bootstrap(&Dllb.query/1) do
      {:ok, :bootstrapped} -> :ok
      {:error, reason} -> Logger.warning("Schema bootstrap issue: #{inspect(reason)}")
    end
  rescue
    _ -> :ok
  end

  defp ingest_one(file_path, language, project_tag, batch_size) do
    context = %{
      language: language,
      file_path: file_path,
      project_path: project_tag
    }

    parse_result =
      IngestTelemetry.span(:file_parse, %{path: file_path, language: language}, fn ->
        Metastatic.Builder.from_file(file_path, language)
      end)

    with {:ok, doc} <- parse_result do
      {creates, relates} =
        IngestTelemetry.span_with_meta(
          :querygen,
          %{path: file_path},
          fn ->
            {c, r} = MetaAST.ingest_tree_queries(doc.ast, context)
            {{c, r}, %{path: file_path, creates: length(c), relates: length(r)}}
          end
        )

      # Upsert (idempotent)
      upserts = Enum.map(creates, &(&1 <> " ON CONFLICT UPDATE"))

      {node_ok, _node_err} =
        IngestTelemetry.span(:batch_nodes, %{path: file_path, count: length(upserts)}, fn ->
          execute_batched(upserts, batch_size)
        end)

      {edge_ok, _edge_err} =
        IngestTelemetry.span(:batch_edges, %{path: file_path, count: length(relates)}, fn ->
          execute_batched(relates, batch_size)
        end)

      {:ok, node_ok, edge_ok}
    end
  rescue
    e -> {:error, {:exception, Exception.message(e)}}
  end

  defp execute_batched(queries, batch_size) do
    queries
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce({0, 0}, fn chunk, {ok_acc, err_acc} ->
      results = Dllb.batch(chunk)

      ok =
        Enum.count(results, fn
          {:ok, %Dllb.Result.Error{}} -> false
          {:ok, _} -> true
          _ -> false
        end)

      {ok_acc + ok, err_acc + (length(results) - ok)}
    end)
  end
end
