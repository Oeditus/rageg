defmodule Rageg.Assess do
  @moduledoc """
  Context module for the PR/Branch Assessment page.

  Wraps the logic from `Mix.Tasks.Ragex.Assess` into a programmatic API
  suitable for driving a LiveView with progress callbacks.

  Runs git diff, static analysis (filtered to changed files), and optionally
  an AI-powered code review assessment report.
  """

  alias Ragex.Agent.{Core, Memory, Report, ToolSchema}
  alias Ragex.AI.Config, as: AIConfig
  alias Ragex.Analysis.Runner
  alias Ragex.Git.Repo

  @max_diff_chars 80_000

  @doc """
  Lists local and remote branches for the given repo path.

  Returns `{:ok, branches}` where branches is a list of maps with `:name`
  and `:current?` keys, or `{:error, reason}`.
  """
  @spec list_branches(String.t()) :: {:ok, list(map())} | {:error, term()}
  def list_branches(repo_path) do
    with {:ok, repo_root} <- Repo.root(repo_path) do
      case System.cmd("git", ["branch", "-a", "--format=%(refname:short) %(HEAD)"],
             cd: repo_root,
             stderr_to_stdout: true
           ) do
        {output, 0} ->
          branches =
            output
            |> String.split("\n", trim: true)
            |> Enum.map(fn line ->
              {name, current?} =
                case String.split(line, " ", parts: 2) do
                  [name, "*"] -> {name, true}
                  [name | _] -> {name, false}
                end

              %{name: name, current?: current?}
            end)
            |> Enum.reject(fn b -> String.contains?(b.name, "HEAD") end)

          {:ok, branches}

        {err, _} ->
          {:error, err}
      end
    end
  end

  @doc """
  Returns the current branch name for a repo path.
  """
  @spec current_branch(String.t()) :: {:ok, String.t()} | {:error, term()}
  def current_branch(repo_path) do
    Repo.current_branch(repo_path)
  end

  @doc """
  Runs the full assessment pipeline for a branch/PR.

  ## Options

    * `:base` - Base ref to diff against (default: `"origin/main"`)
    * `:head` - Head branch (default: current branch)
    * `:format` - `"markdown"` or `"json"` (default: `"markdown"`)
    * `:on_progress` - `(String.t() -> :ok)` callback for progress updates
    * `:provider` - AI provider atom (optional)
    * `:model` - Model name override (optional)

  ## Returns

  `{:ok, result}` where result contains `:report` (string), `:changed_files`,
  `:summary`, and `:format` keys. Or `{:error, reason}`.
  """
  @spec run(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(repo_path, opts \\ []) do
    base = Keyword.get(opts, :base, "origin/main")
    format = Keyword.get(opts, :format, "markdown")
    on_progress = Keyword.get(opts, :on_progress, fn _ -> :ok end)

    with {:ok, repo_root} <- Repo.root(repo_path) do
      head =
        case Keyword.get(opts, :head) do
          nil ->
            case Repo.current_branch(repo_root) do
              {:ok, branch} -> branch
              {:error, reason} -> throw({:branch_error, reason})
            end

          branch ->
            branch
        end

      on_progress.("Diffing #{base}...#{head}")

      case get_changed_files(repo_root, base, head) do
        {:ok, []} ->
          {:ok,
           %{
             report: "No files changed between `#{base}` and `#{head}`.",
             changed_files: [],
             summary: %{total_issues: 0},
             format: format,
             base: base,
             head: head
           }}

        {:ok, changed_files} ->
          on_progress.("#{length(changed_files)} file(s) changed")
          do_assess(repo_root, base, head, changed_files, format, on_progress, opts)

        {:error, reason} ->
          {:error, "Failed to resolve changed files: #{inspect(reason)}"}
      end
    end
  catch
    {:branch_error, reason} -> {:error, "Failed to resolve branch: #{inspect(reason)}"}
  end

  # -- Private Implementation --

  defp do_assess(repo_root, base, head, changed_files, format, on_progress, opts) do
    # Step 1: Analyze project (loads caches, indexes changed files)
    on_progress.("Analyzing project...")

    case Core.analyze_project(repo_root, skip_report: true, verbose: false) do
      {:ok, result} ->
        on_progress.("Project analysis complete")

        # Filter issues to only those in PR's changed files
        changed_set = MapSet.new(changed_files)
        filtered_issues = Runner.filter_results_by_files(result.issues, changed_set)
        issue_count = count_total_issues(filtered_issues)
        on_progress.("#{issue_count} issue(s) found in changed files")

        # Step 2: Get the diff
        on_progress.("Fetching git diff...")

        diff_text =
          case get_diff(repo_root, base, head) do
            {:ok, diff} -> truncate_diff(diff)
            {:error, _} -> ""
          end

        on_progress.("Diff fetched (#{String.length(diff_text)} chars)")

        # Step 3: Generate report
        case format do
          "json" ->
            summary = build_summary(filtered_issues)

            {:ok,
             %{
               report:
                 Jason.encode!(
                   %{
                     timestamp: DateTime.utc_now(),
                     base: base,
                     head: head,
                     changed_files: changed_files,
                     issues: filtered_issues,
                     summary: summary
                   },
                   pretty: true
                 ),
               changed_files: changed_files,
               summary: summary,
               format: "json",
               base: base,
               head: head
             }}

          _ ->
            on_progress.("Generating AI assessment report...")

            case generate_ai_assessment(
                   repo_root,
                   base,
                   head,
                   changed_files,
                   filtered_issues,
                   diff_text,
                   opts,
                   on_progress
                 ) do
              {:ok, markdown_report} ->
                {:ok,
                 %{
                   report: markdown_report,
                   changed_files: changed_files,
                   summary: build_summary(filtered_issues),
                   format: "markdown",
                   base: base,
                   head: head
                 }}

              {:error, reason} ->
                {:error, "AI assessment failed: #{inspect(reason)}"}
            end
        end

      {:error, reason} ->
        {:error, "Project analysis failed: #{inspect(reason)}"}
    end
  end

  defp generate_ai_assessment(
         repo_root,
         base,
         head,
         changed_files,
         filtered_issues,
         diff_text,
         opts,
         on_progress
       ) do
    provider_name = parse_provider(Keyword.get(opts, :provider)) || AIConfig.provider_name()
    config = AIConfig.api_config(provider_name)

    if is_nil(config.api_key) or config.api_key == "" do
      on_progress.("No API key configured – generating basic report")
      {:ok, Report.generate_basic_report(filtered_issues)}
    else
      metadata = %{
        project_path: repo_root,
        issues: filtered_issues,
        analyzed_at: DateTime.utc_now()
      }

      case Memory.new_session(metadata) do
        {:ok, session} ->
          system_prompt = pr_system_prompt(repo_root)
          Memory.add_message(session.id, :system, system_prompt)

          user_prompt =
            pr_user_prompt(base, head, changed_files, filtered_issues, diff_text)

          Memory.add_message(session.id, :user, user_prompt)

          rag_tools = ToolSchema.rag_query_tools(provider_name)

          report_opts =
            [
              tools: rag_tools,
              max_iterations: 4,
              context_max_chars: 128_000
            ]
            |> maybe_put(:provider, parse_provider(Keyword.get(opts, :provider)))
            |> maybe_put(:model, Keyword.get(opts, :model))

          case Ragex.Agent.Executor.run(session.id, report_opts) do
            {:ok, result} ->
              Memory.clear_session(session.id)
              on_progress.("AI assessment report generated")
              {:ok, result.content}

            {:error, reason} ->
              Memory.clear_session(session.id)
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # -- Git helpers --

  defp get_changed_files(repo_root, base, head) do
    args = ["diff", "--name-only", "--diff-filter=ACMR", "#{base}...#{head}"]

    case System.cmd("git", args, cd: repo_root, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.split(output, "\n", trim: true)}
      {err, _} -> {:error, err}
    end
  end

  defp get_diff(repo_root, base, head) do
    case System.cmd("git", ["diff", "#{base}...#{head}"], cd: repo_root, stderr_to_stdout: true) do
      {diff, 0} -> {:ok, diff}
      {err, _} -> {:error, err}
    end
  end

  defp truncate_diff(diff) do
    if String.length(diff) > @max_diff_chars do
      String.slice(diff, 0, @max_diff_chars) <>
        "\n\n[... Diff truncated due to size limit ...]\n"
    else
      diff
    end
  end

  # -- Prompts (mirrors Mix.Tasks.Ragex.Assess) --

  defp pr_system_prompt(project_path) do
    """
    You are a senior software architect performing a pull request (PR) code review and assessment.
    Your deliverable is a comprehensive, constructive, and detailed PR Assessment Report.
    Write as a professional reviewer: precise, evidence-based, and highly actionable.

    PROJECT CONTEXT:
    The project being analyzed is located at: #{project_path}

    IMPORTANT RULES:
    1. You have access to RAG/MCP search tools (like `read_file`, `semantic_search`, `query_graph`, etc.) to query the codebase if you need to fetch extra context. Use them selectively. Do NOT loop calling tools repeatedly.
    2. Be constructive. Highlight good patterns, but focus heavily on identifying bugs, code smells, complexity issues, security concerns, or architectural misalignment.
    3. Be specific: cite filenames, line numbers, function names, and quote code blocks from the diff.
    4. Your entire response must be the Markdown report.

    REPORT STRUCTURE (mandatory sections):

    1. **PR Overview & Summary**
       - Table of metadata: head branch, base branch, total files changed, lines added/removed.
       - A concise summary of the purpose and scope of changes.

    2. **Static Analysis Findings**
       - Summary of static analysis issues in the changed files. If none, state so.

    3. **AI Code Review & Risk Assessment**
       - Detailed walkthrough of the diff.
       - Design risks, architectural impact, potential bugs.

    4. **Actionable Suggestions & Refactoring Recommendations**
       - *Blocking*: Must fix before merging.
       - *Non-blocking / Optional*: Improvements for later.

    5. **Verdict & Score**
       - Verdict: Approved, Approve with Suggestions, or Changes Requested.
       - Overall code change quality score: 1 to 10 with justification.
    """
  end

  defp pr_user_prompt(base, head, changed_files, filtered_issues, diff_text) do
    issues_summary = Report.format_issues_for_llm(filtered_issues)

    """
    Below is the pull request metadata, static analysis findings, and code diff.

    ## Pull Request Metadata
    - Base branch/ref: #{base}
    - Head branch/ref: #{head}
    - Changed files:
    #{Enum.map(changed_files, &"- `#{&1}`") |> Enum.join("\n")}

    ## Static Analysis Findings in Changed Files
    #{issues_summary}

    ## Git Diff (Changes)
    ```diff
    #{diff_text}
    ```
    """
  end

  # -- Counting/Summary helpers --

  defp build_summary(issues) when is_map(issues) do
    %{
      dead_code_count: count_issues(issues[:dead_code]),
      duplicate_count: count_issues(issues[:duplicates]),
      security_count: count_issues(issues[:security]),
      smell_count: count_issues(issues[:smells]),
      complexity_count: count_issues(issues[:complexity]),
      circular_dep_count: count_issues(issues[:circular_deps]),
      suggestion_count: count_issues(issues[:suggestions]),
      total_issues:
        count_issues(issues[:dead_code]) +
          count_issues(issues[:duplicates]) +
          count_issues(issues[:security]) +
          count_issues(issues[:smells]) +
          count_issues(issues[:complexity]) +
          count_issues(issues[:circular_deps])
    }
  end

  defp build_summary(_), do: %{total_issues: 0}

  defp count_issues(nil), do: 0
  defp count_issues(issues) when is_list(issues), do: length(issues)
  defp count_issues(%{items: items}) when is_list(items), do: length(items)
  defp count_issues(%{count: count}) when is_integer(count), do: count
  defp count_issues(_), do: 0

  defp count_total_issues(issues) when is_map(issues) do
    Enum.reduce(issues, 0, fn {_key, value}, acc ->
      acc + count_issues(value)
    end)
  end

  defp count_total_issues(_), do: 0

  defp parse_provider(nil), do: nil

  defp parse_provider(name) when is_binary(name),
    do: String.to_existing_atom(name)

  defp parse_provider(name) when is_atom(name), do: name

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
