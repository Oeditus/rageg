defmodule Rageg.Quality do
  @moduledoc """
  Context module for code quality data.

  Wraps multiple Ragex analysis modules to provide a unified API
  for the Quality LiveView page:

  - `Ragex.Analysis.Smells` -- code smell detection
  - `Ragex.Analysis.Security` -- vulnerability scanning
  - `Ragex.Analysis.DeadCode` -- unused function detection
  - `Ragex.Analysis.Duplication` -- clone detection
  - `Ragex.Analysis.Quality` -- complexity metrics (cyclomatic, cognitive, Halstead)
  - `Ragex.Analysis.BusinessLogic` -- business logic anti-pattern detection

  All functions rescue exceptions and return empty defaults to keep
  the UI resilient even when Ragex has no data loaded.
  """

  alias Ragex.Analysis.{BusinessLogic, DeadCode, Duplication, Quality, Security, Smells}

  @type tab :: :smells | :security | :dead_code | :duplication | :complexity | :business_logic

  @doc "Available tabs with display names and icons."
  @spec tabs() :: [{tab(), String.t(), String.t()}]
  def tabs do
    [
      {:smells, "Code Smells", "hero-exclamation-triangle"},
      {:security, "Security", "hero-shield-exclamation"},
      {:dead_code, "Dead Code", "hero-trash"},
      {:duplication, "Duplication", "hero-document-duplicate"},
      {:complexity, "Complexity", "hero-chart-bar"},
      {:business_logic, "Business Logic", "hero-cog-6-tooth"}
    ]
  end

  @doc """
  Fetches code smells for a path.

  Returns `{:ok, smells_list}` where each smell has `:type`, `:severity`,
  `:description`, `:suggestion`, and optional `:location`.
  """
  @spec fetch_smells(String.t()) :: {:ok, list()} | {:error, term()}
  def fetch_smells(path) do
    case Smells.analyze_directory(path) do
      {:ok, %{results: results}} ->
        smells =
          results
          |> Enum.flat_map(fn result ->
            Enum.map(result.smells, fn smell ->
              smell
              |> Map.put(:file, result.path)
              |> Map.put(:language, result.language)
            end)
          end)
          |> Enum.sort_by(&severity_order(&1.severity))

        {:ok, smells}

      _ ->
        {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end

  @doc """
  Fetches security vulnerabilities for a path.

  Returns `{:ok, vulns_list}` where each vuln has `:category`, `:severity`,
  `:description`, `:recommendation`, `:file`.
  """
  @spec fetch_security(String.t()) :: {:ok, list()} | {:error, term()}
  def fetch_security(path) do
    case Security.analyze_directory(path) do
      {:ok, results} when is_list(results) ->
        vulns =
          results
          |> Enum.flat_map(fn result ->
            Enum.map(result.vulnerabilities, fn vuln ->
              Map.put(vuln, :file, result.file)
            end)
          end)
          |> Enum.sort_by(&severity_order(&1.severity))

        {:ok, vulns}

      _ ->
        {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end

  @doc """
  Fetches dead code (unused functions).

  Returns `{:ok, dead_list}` where each entry has `:function`, `:confidence`,
  `:reason`, `:visibility`, `:module`.
  """
  @spec fetch_dead_code() :: {:ok, list()} | {:error, term()}
  def fetch_dead_code do
    case DeadCode.find_dead_code() do
      {:ok, dead} -> {:ok, dead}
      _ -> {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end

  @doc """
  Fetches code duplicates for a path.

  Returns `{:ok, dupes_list}` where each entry has `:file1`, `:file2`,
  `:clone_type`, `:similarity`.
  """
  @spec fetch_duplication(String.t()) :: {:ok, list()} | {:error, term()}
  def fetch_duplication(path) do
    case Duplication.find_duplicates(path) do
      {:ok, dupes} -> {:ok, dupes}
      _ -> {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end

  @doc """
  Fetches complexity metrics for a path.

  Returns `{:ok, complex_list}` of functions exceeding the threshold.
  """
  @spec fetch_complexity(String.t(), keyword()) :: {:ok, list()} | {:error, term()}
  def fetch_complexity(path, opts \\ []) do
    min = Keyword.get(opts, :min_complexity, 5)

    case Quality.find_complex_code(path, min_complexity: min) do
      {:ok, functions} -> {:ok, functions}
      _ -> {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end

  @doc """
  Fetches business logic issues for a path.

  Returns `{:ok, issues_list}` with analyzer, severity, description per issue.
  """
  @spec fetch_business_logic(String.t()) :: {:ok, list()} | {:error, term()}
  def fetch_business_logic(path) do
    case BusinessLogic.analyze_directory(path) do
      {:ok, %{results: results}} ->
        issues =
          results
          |> Enum.flat_map(fn result ->
            Enum.map(Map.get(result, :issues, []), fn issue ->
              issue
              |> Map.put(:file, result.path)
            end)
          end)

        {:ok, issues}

      _ ->
        {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end

  @doc "Returns summary counts for all quality dimensions."
  @spec summary(String.t()) :: map()
  def summary(path) do
    %{
      smells: safe_count(fn -> fetch_smells(path) end),
      security: safe_count(fn -> fetch_security(path) end),
      dead_code: safe_count(fn -> fetch_dead_code() end),
      duplication: safe_count(fn -> fetch_duplication(path) end),
      complexity: safe_count(fn -> fetch_complexity(path) end),
      business_logic: safe_count(fn -> fetch_business_logic(path) end)
    }
  end

  defp safe_count(fun) do
    case fun.() do
      {:ok, list} when is_list(list) -> length(list)
      _ -> 0
    end
  rescue
    _ -> 0
  end

  defp severity_order(:critical), do: 0
  defp severity_order(:high), do: 1
  defp severity_order(:medium), do: 2
  defp severity_order(:low), do: 3
  defp severity_order(_), do: 4
end
