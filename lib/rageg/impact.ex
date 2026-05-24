defmodule Rageg.Impact do
  @moduledoc """
  Context module for impact analysis.

  Wraps `Ragex.Analysis.Impact` to provide change impact prediction,
  risk scoring, effort estimation, and affected test discovery for
  the Impact LiveView page.
  """

  alias Ragex.Analysis.Impact

  @type node_ref :: String.t()

  @doc """
  Analyzes the impact of changing a function or module.

  `target` is a string like `"MyModule.func/2"` which gets parsed
  into the Ragex node reference format.

  Returns `{:ok, analysis}` with affected count, risk score, callers, etc.
  """
  @spec analyze_change(node_ref(), keyword()) :: {:ok, map()} | {:error, term()}
  def analyze_change(target_string, opts \\ []) do
    target = parse_node_ref(target_string)

    case Impact.analyze_change(target, opts) do
      {:ok, analysis} ->
        {:ok,
         %{
           target: target_string,
           direct_callers: Enum.map(analysis.direct_callers, &format_ref/1),
           all_affected: Enum.map(analysis.all_affected, &format_ref/1),
           affected_count: analysis.affected_count,
           depth: analysis.depth,
           risk_score: Float.round(analysis.risk_score * 1.0, 3),
           importance: Float.round(analysis.importance * 1.0, 3),
           recommendations: analysis.recommendations
         }}

      error ->
        error
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Calculates risk score for a target node.

  Returns a map with `:overall` (0.0-1.0), `:level` (:low/:medium/:high/:critical),
  and individual factor scores.
  """
  @spec risk_score(node_ref()) :: {:ok, map()} | {:error, term()}
  def risk_score(target_string) do
    target = parse_node_ref(target_string)

    case Impact.risk_score(target) do
      {:ok, risk} ->
        {:ok,
         %{
           overall: Float.round(risk.overall * 1.0, 3),
           level: risk.level,
           importance: Float.round(risk.importance * 1.0, 3),
           coupling: Float.round(risk.coupling * 1.0, 3),
           complexity: Float.round(risk.complexity * 1.0, 3)
         }}

      error ->
        error
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Estimates refactoring effort for an operation on a target.

  Returns complexity level, estimated time, risks, and recommendations.
  """
  @spec estimate_effort(atom(), node_ref()) :: {:ok, map()} | {:error, term()}
  def estimate_effort(operation, target_string) do
    target = parse_node_ref(target_string)

    case Impact.estimate_effort(operation, target) do
      {:ok, estimate} ->
        {:ok,
         %{
           operation: estimate.operation,
           target: target_string,
           estimated_changes: estimate.estimated_changes,
           complexity: estimate.complexity,
           estimated_time: estimate.estimated_time,
           risks: estimate.risks,
           recommendations: estimate.recommendations
         }}

      error ->
        error
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Finds tests affected by changing a target.

  Returns a list of test function reference strings.
  """
  @spec find_affected_tests(node_ref()) :: {:ok, [String.t()]} | {:error, term()}
  def find_affected_tests(target_string) do
    target = parse_node_ref(target_string)

    case Impact.find_affected_tests(target) do
      {:ok, tests} -> {:ok, Enum.map(tests, &format_ref/1)}
      error -> error
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc "Supported refactoring operations for effort estimation."
  @spec effort_operations() :: [{atom(), String.t()}]
  def effort_operations do
    [
      {:rename_function, "Rename Function"},
      {:rename_module, "Rename Module"},
      {:extract_function, "Extract Function"},
      {:inline_function, "Inline Function"},
      {:move_function, "Move Function"},
      {:change_signature, "Change Signature"}
    ]
  end

  # -- Private --

  defp parse_node_ref(target) when is_binary(target) do
    cond do
      String.contains?(target, "/") ->
        # "Module.func/2" -> {:function, Module, :func, 2}
        [path, arity_str] = String.split(target, "/", parts: 2)
        arity = String.to_integer(arity_str)

        case String.split(path, ".") |> Enum.split(-1) do
          {mod_parts, [func]} ->
            module = mod_parts |> Enum.join(".") |> String.to_atom()
            {:function, module, String.to_atom(func), arity}

          _ ->
            {:function, String.to_atom(path), :unknown, arity}
        end

      true ->
        # Plain module name
        {:module, String.to_atom(target)}
    end
  end

  defp parse_node_ref(target), do: target

  defp format_ref({:function, mod, name, arity}), do: "#{mod}.#{name}/#{arity}"
  defp format_ref({:module, name}), do: "#{name}"
  defp format_ref(other), do: inspect(other)
end
