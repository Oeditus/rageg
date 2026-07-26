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

    issues = Enum.map(report.issues, &format_issue/1)

    {:ok,
     %{
       source_files_count: length(report.source_files),
       issues: issues,
       summary: format_summary(report.summary),
       timing_ms: report.timing_ms
     }}
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

  # -- Helpers --

  defp format_issue(issue) do
    check_name =
      if is_atom(issue.check) do
        issue.check |> Module.split() |> List.last()
      else
        to_string(issue.check)
      end

    %{
      check: check_name,
      category: issue.category,
      severity: issue.severity || :warning,
      priority: issue.priority || :normal,
      message: issue.message,
      trigger: issue.trigger,
      line_no: issue.line_no,
      column: issue.column,
      filename: issue.filename
    }
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
