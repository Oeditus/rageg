defmodule Rageg.Analyze do
  @moduledoc """
  Context module for the Analysis Runner page.

  Wraps `Ragex.Analysis.Runner` to provide project analysis
  with configurable analysis types and progress reporting.

  Leverages `Ragex.Graph.Store.load_project/1` to restore cached
  graph data, embeddings, and file-tracker state so that only files
  changed since the last run are re-indexed and re-embedded.
  Analysis results are cached via `Ragex.Analysis.Cache`.
  """

  alias Ragex.Analysis.{Cache, Runner}
  alias Ragex.Embeddings.Persistence, as: EmbeddingsPersistence
  alias Ragex.Graph.Persistence, as: GraphPersistence
  alias Ragex.Graph.Store
  alias Ragex.Store.Backend

  require Logger

  @type analysis_key ::
          :security
          | :business_logic
          | :complexity
          | :smells
          | :duplicates
          | :dead_code
          | :dependencies
          | :quality
          | :circulars
          | :god_modules
          | :unstable_modules
          | :unused_modules
          | :coupling

  @doc "Available analysis types with display names and default enabled state."
  @spec analysis_types() :: [{analysis_key(), String.t(), boolean()}]
  def analysis_types do
    [
      {:security, "Security Vulnerabilities", true},
      {:complexity, "Complexity Metrics", true},
      {:smells, "Code Smells", true},
      {:duplicates, "Code Duplication", true},
      {:dead_code, "Dead Code", false},
      {:dependencies, "Dependencies", true},
      {:quality, "Quality Metrics", true},
      {:circulars, "Circular Dependencies", true},
      {:god_modules, "God Modules", true},
      {:unstable_modules, "Unstable Modules", true},
      {:unused_modules, "Unused Modules", true},
      {:coupling, "Coupling Analysis", true},
      {:business_logic, "Business Logic", false}
    ]
  end

  @doc """
  Runs the analysis pipeline on a project directory.

  Loads cached graph/embeddings/file-tracker state first so that
  only changed files are re-indexed and re-embedded.  When the
  analysis cache is completely fresh (no files changed), cached
  analysis results are returned immediately.

  ## Options

    * `:analyses` - map of analysis_key => boolean (which to run)
    * `:on_progress` - `(String.t() -> :ok)` callback for progress updates

  ## Returns

  `{:ok, %{index: map, results: map}}` or `{:error, reason}`
  """
  @spec run(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(path, opts \\ []) do
    analyses = Keyword.get(opts, :analyses, default_analyses())
    on_progress = Keyword.get(opts, :on_progress, fn _ -> :ok end)

    # Restore cached graph, embeddings and file-tracker for this project
    # so the incremental mode in Directory.analyze_directory can skip
    # unchanged files.
    on_progress.("Loading project cache...")
    Store.load_project(path)

    # If the analysis cache is completely fresh, return it immediately.
    case Cache.load(path) do
      {:ok, cached_results} ->
        on_progress.("All files unchanged -- using cached results")

        index_result = %{
          files_analyzed: 0,
          entities_found: extract_node_count(Store.stats()),
          errors: []
        }

        {:ok, %{index: index_result, results: cached_results}}

      _stale_or_missing ->
        do_run(path, analyses, on_progress)
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # Runs the full index + analysis pipeline and persists caches.
  defp do_run(path, analyses, on_progress) do
    on_progress.("Indexing #{path}...")

    case Runner.analyze_directory(path) do
      {:ok, index_result} ->
        on_progress.(
          "Index complete: #{index_result.files_analyzed} files, #{index_result.entities_found} entities"
        )

        enabled_count = analyses |> Enum.count(fn {_k, v} -> v end)
        on_progress.("Running #{enabled_count} analysis passes...")

        config = %{
          path: path,
          severity: [:low, :medium, :high, :critical],
          threshold: 0.8,
          min_complexity: 5,
          god_threshold: 15,
          instability_threshold: 0.7,
          analyses: analyses
        }

        analysis_labels = Map.new(analysis_types(), fn {key, label, _} -> {key, label} end)

        results =
          Runner.run_all(config,
            on_progress: fn key, phase ->
              label = Map.get(analysis_labels, key, to_string(key))

              case phase do
                :start -> on_progress.("Analyzing: #{label}...")
                {:done, count} -> on_progress.("#{label}: #{count} issue(s) found")
              end
            end
          )

        # Persist caches so the next run can skip unchanged work.
        on_progress.("Saving caches...")
        persist_caches(path, results)

        on_progress.("Analysis complete")
        {:ok, %{index: index_result, results: results}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist_caches(path, results) do
    # ETS-based persistence is only meaningful when the ETS backend is active.
    # When dllb is the backend, data is already persisted in the database.
    if Backend.module() == Ragex.Store.Backend.ETS do
      EmbeddingsPersistence.save(nil, path)
      GraphPersistence.save(path)
    end

    Cache.save(results, path)
  rescue
    e -> Logger.warning("Failed to persist caches: #{Exception.message(e)}")
  end

  # Normalizes the node count from Store.stats(), which differs by backend:
  #   ETS  -> %{nodes: N, edges: M, embeddings: K}
  #   dllb -> %{total: N, by_kind: %{...}}
  defp extract_node_count(%{nodes: n}) when is_integer(n), do: n
  defp extract_node_count(%{total: n}) when is_integer(n), do: n
  defp extract_node_count(_), do: 0

  @doc "Returns the default analysis map with all types enabled per defaults."
  @spec default_analyses() :: %{analysis_key() => boolean()}
  def default_analyses do
    Map.new(analysis_types(), fn {key, _label, default} -> {key, default} end)
  end
end
