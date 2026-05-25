defmodule Rageg.Profiles.DllbIngestor do
  @moduledoc """
  Ingests source files into the dllb database as MetaAST nodes and edges.

  Mirrors the pipeline from `Mix.Tasks.Dllb.Ingest` but is callable
  as a regular function with progress callbacks. Uses
  `Dllb.MetaAST.ingest_tree_queries/2` to generate queries and
  `Dllb.batch/1` to execute them efficiently.
  """

  require Logger

  alias Dllb.MetaAST
  alias Rageg.Profiles.FileDiscovery

  @batch_size 100

  @type ingest_result :: %{
          files_ok: non_neg_integer(),
          files_err: non_neg_integer(),
          nodes: non_neg_integer(),
          edges: non_neg_integer()
        }

  @type progress_fn :: (String.t() -> :ok)

  @doc """
  Bootstraps the dllb schema (idempotent) and ingests all source files
  under the given path.

  ## Options

    * `:project_tag` - value for the `project_path` field (required)
    * `:on_progress` - `(String.t() -> :ok)` callback for status messages
    * `:batch_size` - queries per batch (default: #{@batch_size})

  ## Returns

  `{:ok, ingest_result}` or `{:error, reason}`
  """
  @spec ingest(String.t(), keyword()) :: {:ok, ingest_result()} | {:error, term()}
  def ingest(path, opts \\ []) do
    project_tag = Keyword.fetch!(opts, :project_tag)
    on_progress = Keyword.get(opts, :on_progress, fn _ -> :ok end)
    batch_size = Keyword.get(opts, :batch_size, @batch_size)

    on_progress.("Bootstrapping dllb schema...")
    bootstrap_schema!()

    files = FileDiscovery.discover(path)
    total = length(files)
    on_progress.("Discovered #{total} source files")

    if total == 0 do
      {:ok, %{files_ok: 0, files_err: 0, nodes: 0, edges: 0}}
    else
      result =
        files
        |> Enum.with_index(1)
        |> Enum.reduce(%{files_ok: 0, files_err: 0, nodes: 0, edges: 0}, fn {{file_path, lang},
                                                                             idx},
                                                                            acc ->
          on_progress.("Ingesting [#{idx}/#{total}] #{Path.relative_to_cwd(file_path)}")

          case ingest_one(file_path, lang, project_tag, batch_size) do
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
        end)

      Rageg.Dllb.save_ingest_stats(project_tag, result)
      on_progress.("Done: #{result.files_ok} files, #{result.nodes} nodes, #{result.edges} edges")
      {:ok, result}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # -- Private --

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

    with {:ok, doc} <- Metastatic.Builder.from_file(file_path, language) do
      {creates, relates} = MetaAST.ingest_tree_queries(doc.ast, context)

      # Upsert (idempotent)
      upserts = Enum.map(creates, &(&1 <> " ON CONFLICT UPDATE"))
      {node_ok, _node_err} = execute_batched(upserts, batch_size)
      {edge_ok, _edge_err} = execute_batched(relates, batch_size)

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
