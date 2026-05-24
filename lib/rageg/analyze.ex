defmodule Rageg.Analyze do
  @moduledoc """
  Context module for the Analysis Runner page.

  Wraps `Ragex.Analysis.Runner` to provide project analysis
  with configurable analysis types and progress reporting.
  """

  alias Ragex.Analysis.Runner

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

  First indexes the directory into the knowledge graph, then runs
  all enabled analyses.

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

    on_progress.("Indexing #{path}...")

    case Runner.analyze_directory(path) do
      {:ok, index_result} ->
        on_progress.(
          "Index complete: #{index_result.files_analyzed} files, #{index_result.entities_found} entities"
        )

        config = %{
          path: path,
          severity: [:low, :medium, :high, :critical],
          threshold: 0.8,
          min_complexity: 5,
          god_threshold: 15,
          instability_threshold: 0.7,
          analyses: analyses
        }

        on_progress.("Running analyses...")
        results = Runner.run_all(config)
        on_progress.("Analysis complete")

        {:ok, %{index: index_result, results: results}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc "Returns the default analysis map with all types enabled per defaults."
  @spec default_analyses() :: %{analysis_key() => boolean()}
  def default_analyses do
    Map.new(analysis_types(), fn {key, _label, default} -> {key, default} end)
  end
end
