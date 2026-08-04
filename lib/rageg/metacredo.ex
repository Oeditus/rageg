defmodule Rageg.Metacredo do
  @moduledoc """
  Context module for MetaCredo static code analysis.

  Wraps `MetaCredo.Execution.run/1` to analyze AST nodes across languages
  and present structured issues and metrics to the GUI.
  """

  @type issue_map :: %{
          check: String.t(),
          category: atom(),
          severity: atom(),
          priority: atom() | integer(),
          message: String.t(),
          trigger: String.t() | nil,
          line_no: pos_integer() | nil,
          column: pos_integer() | nil,
          filename: String.t() | nil
        }

  @type result :: %{
          source_files_count: non_neg_integer(),
          issues: [issue_map()],
          summary: map(),
          timing_ms: non_neg_integer()
        }

  @cache_dir "~/.rageg/.metacredo_cache"

  @doc """
  Runs MetaCredo analysis on the specified directory path.
  """
  @spec analyze(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def analyze(path, opts \\ []) do
    strict? = Keyword.get(opts, :strict, false)
    categories = Keyword.get(opts, :categories, nil)

    run_opts = [
      files_included: [path],
      strict: strict?
    ]

    run_opts =
      if categories && categories != [] do
        Keyword.put(run_opts, :only, categories)
      else
        run_opts
      end

    report = MetaCredo.Execution.run(run_opts)
    Metastatic.Cache.clear()

    files_cache = :ets.new(:metacredo_file_cache, [:set, :private])
    issues = Enum.map(report.issues, &format_issue(&1, path, files_cache))
    :ets.delete(files_cache)

    result = %{
      source_files_count: length(report.source_files),
      issues: issues,
      summary: format_summary(report.summary),
      timing_ms: report.timing_ms
    }

    save_cached_result(path, result)

    {:ok, result}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Returns all available MetaCredo check categories.
  """
  @spec categories() :: [atom()]
  def categories do
    [
      :consistency,
      :design,
      :readability,
      :refactor,
      :warning,
      :security,
      :performance,
      :observability
    ]
  end

  @doc """
  Retrieves cached MetaCredo analysis result for a project path.
  """
  @spec get_cached_result(String.t()) :: result() | nil
  def get_cached_result(path) when is_binary(path) and path != "" do
    if dllb_available?() do
      case get_cached_result_dllb(path) do
        nil -> get_cached_result_file(path)
        res -> res
      end
    else
      get_cached_result_file(path)
    end
  end

  def get_cached_result(_), do: nil

  @doc """
  Persists MetaCredo analysis result for a project path.
  """
  @spec save_cached_result(String.t(), result()) :: :ok
  def save_cached_result(path, result) when is_binary(path) and is_map(result) do
    if dllb_available?() do
      save_cached_result_dllb(path, result)
    end

    save_cached_result_file(path, result)
  end

  defp get_cached_result_file(path) do
    cache_file = cache_path(path)

    case File.read(cache_file) do
      {:ok, json_str} ->
        case decode_result(json_str) do
          {:ok, result} -> result
          _ -> nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp save_cached_result_file(path, result) do
    cache_file = cache_path(path)
    File.mkdir_p!(Path.dirname(cache_file))
    File.write!(cache_file, encode_result(result))
    :ok
  rescue
    _ -> :ok
  end

  defp dllb_available? do
    Application.get_env(:dllb, :enabled, false) &&
      match?({:ok, %Dllb.Result.Rows{}}, Dllb.query("SELECT * FROM _dllb_ping_"))
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  defp get_cached_result_dllb(path) do
    id = cache_id(path)

    case Dllb.query("SELECT * FROM _metacredo_cache:#{id}") do
      {:ok, %Dllb.Result.Rows{data: [row | _]}} ->
        payload = row["payload"] || row[:payload]

        if payload && is_binary(payload) do
          case decode_result(payload) do
            {:ok, res} -> res
            _ -> nil
          end
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  defp save_cached_result_dllb(path, result) do
    id = cache_id(path)
    json = encode_result(result)
    escaped_json = String.replace(json, "'", "''")
    query = "CREATE _metacredo_cache:#{id} SET payload = '#{escaped_json}' ON CONFLICT UPDATE"
    Dllb.query(query)
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp cache_id(path) do
    "m_" <> (:crypto.hash(:sha256, path) |> Base.encode16(case: :lower))
  end

  # -- Helpers --

  defp cache_path(path) do
    safe_name = :crypto.hash(:sha256, path) |> Base.encode16(case: :lower)
    Path.expand(Path.join(@cache_dir, "#{safe_name}.json"))
  end

  defp encode_result(result) do
    Jason.encode!(result)
  end

  defp decode_result(json_str) do
    case Jason.decode(json_str) do
      {:ok, map} ->
        result = %{
          source_files_count: Map.get(map, "source_files_count", 0),
          timing_ms: Map.get(map, "timing_ms", 0),
          issues: Enum.map(Map.get(map, "issues", []), &decode_issue/1),
          summary: decode_summary(Map.get(map, "summary", %{}))
        }

        {:ok, result}

      err ->
        err
    end
  end

  defp decode_issue(issue_map) do
    %{
      check: Map.get(issue_map, "check"),
      category: parse_atom(Map.get(issue_map, "category"), :readability),
      severity: parse_atom(Map.get(issue_map, "severity"), :warning),
      priority: Map.get(issue_map, "priority"),
      message: Map.get(issue_map, "message"),
      trigger: Map.get(issue_map, "trigger"),
      line_no: Map.get(issue_map, "line_no"),
      column: Map.get(issue_map, "column"),
      filename: Map.get(issue_map, "filename"),
      snippet: decode_snippet(Map.get(issue_map, "snippet")),
      suggestion: Map.get(issue_map, "suggestion")
    }
  end

  defp parse_atom(val, default) when is_binary(val) do
    String.to_existing_atom(val)
  rescue
    _ -> default
  end

  defp parse_atom(val, _default) when is_atom(val), do: val
  defp parse_atom(_val, default), do: default

  defp decode_snippet(nil), do: nil

  defp decode_snippet(s) when is_map(s) do
    %{
      start_line: Map.get(s, "start_line", 1),
      lines:
        Enum.map(Map.get(s, "lines", []), fn line ->
          %{
            line_no: Map.get(line, "line_no"),
            content: Map.get(line, "content", ""),
            is_target: Map.get(line, "is_target", false)
          }
        end)
    }
  end

  defp decode_summary(summary_map) do
    by_category =
      summary_map
      |> Map.get("by_category", %{})
      |> Map.new(fn {k, v} -> {parse_atom(k, :readability), v} end)

    by_severity =
      summary_map
      |> Map.get("by_severity", %{})
      |> Map.new(fn {k, v} -> {parse_atom(k, :warning), v} end)

    %{
      total: Map.get(summary_map, "total", 0),
      by_category: by_category,
      by_severity: by_severity,
      by_check: Map.get(summary_map, "by_check", %{})
    }
  end

  defp format_issue(issue, project_path, files_cache) do
    check_name =
      if is_atom(issue.check) do
        issue.check |> Module.split() |> List.last()
      else
        to_string(issue.check)
      end

    formatted = %{
      check: check_name,
      category: issue.category,
      severity: issue.severity || :warning,
      priority: issue.priority || :normal,
      message: issue.message,
      trigger: issue.trigger,
      line_no: issue.line_no,
      column: issue.column,
      filename: issue.filename,
      snippet: extract_snippet(issue.filename, issue.line_no, project_path, files_cache)
    }

    Map.put(formatted, :suggestion, suggest_fix(formatted))
  end

  defp extract_snippet(filename, line_no, project_path, files_cache)
       when is_binary(filename) and is_integer(line_no) and line_no > 0 do
    possible_paths = [
      filename,
      Path.join(project_path || "", filename)
    ]

    resolved_path = Enum.find(possible_paths, &File.regular?/1)

    if resolved_path do
      all_lines =
        case :ets.lookup(files_cache, resolved_path) do
          [{^resolved_path, cached}] ->
            cached

          [] ->
            case File.read(resolved_path) do
              {:ok, content} ->
                lines = String.split(content, ~r/\r?\n/)
                :ets.insert(files_cache, {resolved_path, lines})
                lines

              _ ->
                nil
            end
        end

      if all_lines do
        total_lines = length(all_lines)

        if line_no <= total_lines do
          context_radius = 2
          start_line = max(1, line_no - context_radius)
          end_line = min(total_lines, line_no + context_radius)

          lines_slice =
            all_lines
            |> Enum.slice((start_line - 1)..(end_line - 1))
            |> Enum.with_index(start_line)
            |> Enum.map(fn {line_content, idx} ->
              %{
                line_no: idx,
                content: line_content,
                is_target: idx == line_no
              }
            end)

          %{
            start_line: start_line,
            lines: lines_slice
          }
        else
          nil
        end
      else
        nil
      end
    else
      nil
    end
  rescue
    _ -> nil
  end

  defp extract_snippet(_filename, _line_no, _project_path, _files_cache), do: nil

  defp suggest_fix(issue) do
    check = to_string(issue.check || "")
    category = issue.category
    msg = issue.message || ""
    trigger = issue.trigger

    cond do
      String.contains?(check, "ModuleDoc") ->
        "Add a `@moduledoc \"\"\"...\"\"\"` block explaining the purpose of this module, or specify `@moduledoc false` if it is an internal module."

      String.contains?(check, "SinglePipe") ->
        "Replace single-stage pipe with a direct function call (e.g., `f(x)` instead of `x |> f()`)."

      String.contains?(check, "Unused") or String.contains?(msg, "unused") ->
        if trigger do
          "Prefix unused variable `#{trigger}` with an underscore (e.g., `_#{trigger}`) or remove it if redundant."
        else
          "Prefix unused variables with an underscore or remove them."
        end

      String.contains?(check, "FunctionArity") or String.contains?(check, "LargeModule") or
          String.contains?(check, "Complexity") ->
        "Refactor into smaller, single-responsibility functions or split large modules into dedicated sub-modules."

      String.contains?(check, "TODO") or String.contains?(check, "FIXME") or
          String.contains?(msg, "TODO") ->
        "Address or resolve the TODO/FIXME annotation before committing."

      category == :security ->
        "Validate input arguments, sanitize dynamic data, and ensure secure configuration defaults."

      category == :performance ->
        "Avoid redundant function calls inside loops and prefer lazy evaluation or streaming for large collections."

      category == :readability ->
        "Improve code layout, use clear variable names, and conform to community style guidelines."

      category == :refactor ->
        "Simplify conditional logic or extract complex expressions into descriptive helper functions."

      category == :consistency ->
        "Ensure consistent naming, formatting, and pattern structure across the codebase."

      true ->
        "Review the issue context and apply standard clean-code refactoring practices."
    end
  end

  defp format_summary(summary) do
    %{
      total: Map.get(summary, :total, 0),
      by_category: Map.get(summary, :by_category, %{}),
      by_severity: Map.get(summary, :by_severity, %{}),
      by_check: Map.get(summary, :by_check, %{})
    }
  end
end
