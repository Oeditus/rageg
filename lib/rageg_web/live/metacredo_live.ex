defmodule RagegWeb.MetacredoLive do
  @moduledoc """
  LiveView page for MetaCredo static code analysis.

  Allows running cross-language MetaAST checks against the active project
  profile with options for strict mode, category filtering, and real-time
  issue exploration.
  """

  use RagegWeb, :live_view

  alias Rageg.Metacredo

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    active_path =
      case Rageg.Profiles.active() do
        %{path: p} -> p
        _ -> ""
      end

    {:ok,
     socket
     |> assign(page_title: gettext("MetaCredo Analysis"))
     |> assign(current_path: "/metacredo")
     |> assign(project_path: active_path)
     |> assign(strict: false)
     |> assign(selected_category: "all")
     |> assign(search_query: "")
     |> assign(running: false)
     |> assign(result: nil)
     |> assign(error: nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_strict", %{"strict" => val}, socket) do
    strict? = val == "true" or val == "on"
    {:noreply, assign(socket, strict: strict?)}
  end

  def handle_event("toggle_strict", _params, socket) do
    {:noreply, assign(socket, strict: !socket.assigns.strict)}
  end

  def handle_event("filter_category", %{"category" => cat}, socket) do
    {:noreply, assign(socket, selected_category: cat)}
  end

  def handle_event("update_search", %{"query" => q}, socket) do
    {:noreply, assign(socket, search_query: q)}
  end

  def handle_event("run_analysis", _params, socket) do
    path = socket.assigns.project_path

    if path == "" or not File.dir?(path) do
      {:noreply,
       assign(socket, error: gettext("No valid active profile path. Select a profile first."))}
    else
      pid = self()
      strict? = socket.assigns.strict

      {:ok, task_pid} =
        Task.start(fn ->
          res = Metacredo.analyze(path, strict: strict?)
          send(pid, {:analysis_complete, res})
        end)

      Process.monitor(task_pid)

      {:noreply, assign(socket, running: true, error: nil)}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:rageg_profile_changed, profile}, socket) do
    path = (profile && profile.path) || ""
    {:noreply, assign(socket, project_path: path, result: nil, error: nil)}
  end

  def handle_info({:analysis_complete, {:ok, result}}, socket) do
    {:noreply, assign(socket, running: false, result: result, error: nil)}
  end

  def handle_info({:analysis_complete, {:error, reason}}, socket) do
    {:noreply, assign(socket, running: false, error: to_string(reason))}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, assign(socket, running: false)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold flex items-center gap-2">
            <.icon name="hero-check-badge" class="size-7 text-primary" />
            {gettext("MetaCredo Static Analysis")}
          </h1>
          <p class="text-sm text-base-content/60 mt-1">
            {gettext("Cross-language MetaAST code quality and compliance inspector.")}
          </p>
        </div>

        <div class="flex items-center gap-3">
          <label class="cursor-pointer label gap-2 bg-base-200 px-3 py-1.5 rounded-lg border border-base-300">
            <span class="label-text text-sm font-medium">{gettext("Strict Mode")}</span>
            <input
              type="checkbox"
              id="metacredo-strict-toggle"
              class="toggle toggle-primary toggle-sm"
              checked={@strict}
              phx-click="toggle_strict"
            />
          </label>

          <button
            id="metacredo-run-btn"
            class="btn btn-primary gap-2"
            phx-click="run_analysis"
            disabled={@running or @project_path == ""}
          >
            <span :if={@running} class="loading loading-spinner loading-sm"></span>
            <.icon :if={!@running} name="hero-play" class="size-5" />
            {if @running, do: gettext("Analyzing..."), else: gettext("Run Analysis")}
          </button>
        </div>
      </div>

      <%!-- Active project info --%>
      <div class="alert bg-base-200 border-base-300 shadow-sm flex items-center justify-between">
        <div class="flex items-center gap-2 text-sm font-mono truncate">
          <.icon name="hero-folder" class="size-4 text-secondary shrink-0" />
          <span class="text-base-content/60">{gettext("Target Path")}:</span>
          <span class="font-bold truncate">{if @project_path == "", do: gettext("None selected"), else: @project_path}</span>
        </div>
        <span :if={@result} class="badge badge-outline text-xs shrink-0">
          {@result.source_files_count} {gettext("files inspected")} ({@result.timing_ms} ms)
        </span>
      </div>

      <%!-- Error alert --%>
      <div :if={@error} class="alert alert-error" id="metacredo-error">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>{@error}</span>
      </div>

      <%!-- Results section --%>
      <div :if={@result} class="space-y-6" id="metacredo-results">
        <%!-- Summary Cards --%>
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
          <div class="stat bg-base-200 rounded-box border border-base-300 p-4">
            <div class="stat-title text-xs font-medium uppercase tracking-wider">{gettext("Total Issues")}</div>
            <div class={[
              "stat-value text-2xl mt-1",
              if(@result.summary.total > 0, do: "text-warning", else: "text-success")
            ]}>
              {@result.summary.total}
            </div>
            <div class="stat-desc text-xs mt-1">{gettext("across all MetaAST checks")}</div>
          </div>

          <div class="stat bg-base-200 rounded-box border border-base-300 p-4">
            <div class="stat-title text-xs font-medium uppercase tracking-wider">{gettext("Files Analyzed")}</div>
            <div class="stat-value text-2xl mt-1 text-info">{@result.source_files_count}</div>
            <div class="stat-desc text-xs mt-1">{gettext("supported source files")}</div>
          </div>

          <div class="stat bg-base-200 rounded-box border border-base-300 p-4">
            <div class="stat-title text-xs font-medium uppercase tracking-wider">{gettext("Execution Time")}</div>
            <div class="stat-value text-2xl mt-1 text-secondary">{@result.timing_ms} ms</div>
            <div class="stat-desc text-xs mt-1">{gettext("parallel AST pipeline")}</div>
          </div>

          <div class="stat bg-base-200 rounded-box border border-base-300 p-4">
            <div class="stat-title text-xs font-medium uppercase tracking-wider">{gettext("Categories")}</div>
            <div class="stat-value text-2xl mt-1 text-accent">{map_size(@result.summary.by_category)}</div>
            <div class="stat-desc text-xs mt-1">{gettext("active categories triggered")}</div>
          </div>
        </div>

        <%!-- Filter & Search toolbar --%>
        <div class="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3 bg-base-200 p-3 rounded-xl border border-base-300">
          <div class="flex flex-wrap items-center gap-1.5">
            <button
              class={[
                "btn btn-xs rounded-lg",
                if(@selected_category == "all", do: "btn-primary", else: "btn-ghost")
              ]}
              phx-click="filter_category"
              phx-value-category="all"
            >
              {gettext("All")} ({length(@result.issues)})
            </button>
            <%= for cat <- Metacredo.categories() do %>
              <button
                :if={Map.get(@result.summary.by_category, cat, 0) > 0}
                class={[
                  "btn btn-xs rounded-lg capitalize",
                  if(@selected_category == to_string(cat), do: "btn-primary", else: "btn-ghost")
                ]}
                phx-click="filter_category"
                phx-value-category={to_string(cat)}
              >
                {cat} ({Map.get(@result.summary.by_category, cat, 0)})
              </button>
            <% end %>
          </div>

          <div class="form-control w-full sm:w-64">
            <input
              type="text"
              id="metacredo-search-input"
              value={@search_query}
              placeholder={gettext("Search issues or files...")}
              class="input input-sm input-bordered font-mono"
              phx-keyup="update_search"
              phx-value-query=""
            />
          </div>
        </div>

        <%!-- Issues List --%>
        <% filtered = filter_issues(@result.issues, @selected_category, @search_query) %>

        <div :if={filtered == []} class="card bg-base-200 border border-base-300 text-center p-8">
          <.icon name="hero-check-circle" class="size-12 text-success mx-auto mb-3" />
          <h3 class="font-bold text-lg">{gettext("No issues found")}</h3>
          <p class="text-xs text-base-content/60 mt-1">
            {gettext("No MetaCredo code quality violations matched your current filters.")}
          </p>
        </div>

        <div :if={filtered != []} class="space-y-3" id="metacredo-issues-list">
          <div
            :for={issue <- filtered}
            class="card bg-base-200 border border-base-300 hover:border-primary/50 transition-colors shadow-xs"
          >
            <div class="card-body p-4 space-y-2">
              <div class="flex flex-wrap items-center justify-between gap-2">
                <div class="flex items-center gap-2">
                  <span class={["badge badge-sm font-semibold capitalize", severity_badge_class(issue.severity)]}>
                    {issue.severity}
                  </span>
                  <span class="badge badge-sm badge-outline font-mono text-xs capitalize">
                    {issue.category}
                  </span>
                  <span class="font-mono text-xs font-bold text-primary">
                    {issue.check}
                  </span>
                </div>

                <div :if={issue.filename} class="text-xs font-mono text-base-content/70">
                  {issue.filename}{if issue.line_no, do: ":#{issue.line_no}", else: ""}{if issue.column, do: ":#{issue.column}", else: ""}
                </div>
              </div>

              <p class="text-sm font-medium text-base-content">
                {issue.message}
              </p>

              <div :if={issue.trigger} class="bg-base-300 rounded p-2 text-xs font-mono text-base-content/80 overflow-x-auto">
                <code>{issue.trigger}</code>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -- Private helpers --

  defp filter_issues(issues, category, search_query) do
    issues
    |> Enum.filter(fn issue ->
      if category == "all" do
        true
      else
        to_string(issue.category) == category
      end
    end)
    |> Enum.filter(fn issue ->
      if search_query == "" do
        true
      else
        q = String.downcase(search_query)
        msg = String.downcase(issue.message || "")
        file = String.downcase(issue.filename || "")
        check = String.downcase(issue.check || "")

        String.contains?(msg, q) or String.contains?(file, q) or String.contains?(check, q)
      end
    end)
  end

  defp severity_badge_class(:error), do: "badge-error"
  defp severity_badge_class(:warning), do: "badge-warning"
  defp severity_badge_class(:info), do: "badge-info"
  defp severity_badge_class(:refactoring_opportunity), do: "badge-secondary"
  defp severity_badge_class(_), do: "badge-ghost"
end
