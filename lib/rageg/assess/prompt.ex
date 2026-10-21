defmodule Rageg.Assess.Prompt do
  @moduledoc """
  Prompt templates for the PR/branch assessment AI review.

  Extracted from `Rageg.Assess` to keep that module focused on orchestration
  and git plumbing.
  """

  alias Ragex.Agent.Report

  @doc "System prompt for the PR review agent."
  @spec system(String.t()) :: String.t()
  def system(project_path) do
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

  @doc "User prompt carrying the PR metadata, findings, and diff."
  @spec user(String.t(), String.t(), [String.t()], term(), String.t()) :: String.t()
  def user(base, head, changed_files, filtered_issues, diff_text) do
    issues_summary = Report.format_issues_for_llm(filtered_issues)

    """
    Below is the pull request metadata, static analysis findings, and code diff.

    ## Pull Request Metadata
    - Base branch/ref: #{base}
    - Head branch/ref: #{head}
    - Changed files:
    #{Enum.map_join(changed_files, "\n", &"- `#{&1}`")}

    ## Static Analysis Findings in Changed Files
    #{issues_summary}

    ## Git Diff (Changes)
    ```diff
    #{diff_text}
    ```
    """
  end
end
