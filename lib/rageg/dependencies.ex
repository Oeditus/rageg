defmodule Rageg.Dependencies do
  @moduledoc """
  Context module for dependency analysis data.

  Wraps `Ragex.Analysis.DependencyGraph` to provide module coupling,
  instability, circular dependencies, god modules, and unused modules
  for the Dependencies LiveView page.
  """

  alias Ragex.Analysis.DependencyGraph

  @type coupling_entry :: %{
          module: String.t(),
          afferent: non_neg_integer(),
          efferent: non_neg_integer(),
          instability: float(),
          total: non_neg_integer()
        }

  @doc """
  Fetches coupling metrics for all modules, sorted by instability descending.

  Returns `{:ok, [coupling_entry]}`.
  """
  @spec fetch_coupling() :: {:ok, [coupling_entry()]}
  def fetch_coupling do
    case DependencyGraph.all_coupling_metrics(sort_by: :instability, descending: true) do
      {:ok, metrics} ->
        entries =
          Enum.map(metrics, fn {module, m} ->
            %{
              module: to_string(module),
              afferent: m.afferent,
              efferent: m.efferent,
              instability: Float.round(m.instability * 1.0, 3),
              total: m.afferent + m.efferent
            }
          end)

        {:ok, entries}

      {:error, _} ->
        {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end

  @doc """
  Fetches circular dependency cycles at module level.

  Returns `{:ok, cycles}` where each cycle is a list of module name strings.
  """
  @spec fetch_circular_deps() :: {:ok, [[String.t()]]}
  def fetch_circular_deps do
    case DependencyGraph.find_cycles(scope: :module) do
      {:ok, cycles} ->
        formatted =
          Enum.map(cycles, fn cycle ->
            Enum.map(cycle, &to_string/1)
          end)

        {:ok, formatted}

      {:error, _} ->
        {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end

  @doc """
  Fetches god modules exceeding the given coupling threshold.

  Returns `{:ok, [coupling_entry]}`.
  """
  @spec fetch_god_modules(non_neg_integer()) :: {:ok, [coupling_entry()]}
  def fetch_god_modules(threshold \\ 15) do
    case DependencyGraph.find_god_modules(threshold) do
      {:ok, god_modules} ->
        entries =
          Enum.map(god_modules, fn {module, m} ->
            %{
              module: to_string(module),
              afferent: m.afferent,
              efferent: m.efferent,
              instability: Float.round(m.instability * 1.0, 3),
              total: m.afferent + m.efferent
            }
          end)

        {:ok, entries}

      {:error, _} ->
        {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end

  @doc """
  Fetches modules with no incoming references (potentially unused).

  Returns `{:ok, [module_name_string]}`.
  """
  @spec fetch_unused_modules() :: {:ok, [String.t()]}
  def fetch_unused_modules do
    case DependencyGraph.find_unused() do
      {:ok, unused} -> {:ok, Enum.map(unused, &to_string/1)}
      {:error, _} -> {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end

  @doc """
  Returns a summary map with counts for the dependencies page header.
  """
  @spec summary() :: map()
  def summary do
    coupling = safe_fetch(fn -> fetch_coupling() end)
    circulars = safe_fetch(fn -> fetch_circular_deps() end)
    god = safe_fetch(fn -> fetch_god_modules() end)
    unused = safe_fetch(fn -> fetch_unused_modules() end)

    unstable =
      Enum.count(coupling, fn entry ->
        entry.instability > 0.7
      end)

    %{
      total_modules: length(coupling),
      circular_cycles: length(circulars),
      god_modules: length(god),
      unused_modules: length(unused),
      unstable_modules: unstable
    }
  end

  @doc "Available tabs with display names and icons."
  def tabs do
    [
      {:coupling, "Coupling", "hero-arrows-right-left"},
      {:circular, "Circular Deps", "hero-arrow-path"},
      {:god_modules, "God Modules", "hero-exclamation-triangle"},
      {:unused, "Unused Modules", "hero-trash"}
    ]
  end

  defp safe_fetch(fun) do
    case fun.() do
      {:ok, list} when is_list(list) -> list
      _ -> []
    end
  rescue
    _ -> []
  end
end
