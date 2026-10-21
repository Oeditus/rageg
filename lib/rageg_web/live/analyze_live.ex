defmodule RagegWeb.AnalyzeLive do
  @moduledoc """
  Analysis Runner page -- configure and run Ragex analysis pipeline.

  Features:
  - Local project directory analysis (13 configurable analysis types)
  - Remote URL & Git Repository analysis via Ragex.URLAnalyzer
  - Progress messages during indexing and analysis
  - Results summary with issue counts and links to detail pages
  """

  use RagegWeb, :live_view

  alias Rageg.Analyze

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    analyses = Analyze.default_analyses()

    active_path =
      case Rageg.Profiles.active() do
        %{path: p} -> p
        _ -> ""
      end

    {:ok,
     socket
     |> assign(page_title: gettext("Run Analysis"))
     |> assign(current_path: "/analyze")
     |> assign(mode: :local)
     |> assign(project_path: active_path)
     |> assign(analyses: analyses)
     |> assign(url_input: "")
     |> assign(url_depth: "shallow")
     |> assign(url_index_graph: true)
     |> assign(url_auth_token: "")
     |> assign(url_result: nil)
     |> assign(running: false)
     |> assign(task_pid: nil)
     |> assign(progress: [])
     |> assign(results: nil)
     |> assign(index_result: nil)
     |> assign(error: nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("select_mode", %{"mode" => mode_str}, socket) do
    mode = if mode_str == "url", do: :url, else: :local
    {:noreply, assign(socket, mode: mode, error: nil)}
  end

  def handle_event("update_path", %{"path" => path}, socket) do
    {:noreply, assign(socket, project_path: path)}
  end

  def handle_event("update_url", %{"url" => url}, socket) do
    {:noreply, assign(socket, url_input: url)}
  end

  def handle_event("update_url_opts", params, socket) do
    depth = Map.get(params, "depth", socket.assigns.url_depth)
    auth_token = Map.get(params, "auth_token", socket.assigns.url_auth_token)
    index_graph = Map.get(params, "index_graph", "true") == "true"

    {:noreply,
     assign(socket,
       url_depth: depth,
       url_auth_token: auth_token,
       url_index_graph: index_graph
     )}
  end

  def handle_event("toggle_analysis", %{"key" => key}, socket) do
    key_atom = String.to_existing_atom(key)
    analyses = Map.update!(socket.assigns.analyses, key_atom, &(!&1))
    {:noreply, assign(socket, analyses: analyses)}
  end

  def handle_event("run_analysis", _params, socket) do
    path = socket.assigns.project_path

    if path == "" do
      {:noreply, assign(socket, error: gettext("Enter a project path"))}
    else
      pid = self()
      analyses = socket.assigns.analyses

      {:ok, task_pid} =
        Task.start(fn ->
          result =
            Analyze.run(path,
              analyses: analyses,
              on_progress: fn msg -> send(pid, {:progress, msg}) end
            )

          send(pid, {:analysis_complete, result})
        end)

      ref = Process.monitor(task_pid)

      {:noreply,
       assign(socket,
         running: true,
         task_pid: task_pid,
         task_ref: ref,
         error: nil,
         results: nil,
         progress: []
       )}
    end
  end

  def handle_event("run_url_analysis", _params, socket) do
    url = String.trim(socket.assigns.url_input)

    if url == "" do
      {:noreply, assign(socket, error: gettext("Enter a target URL or Git repository"))}
    else
      pid = self()

      opts = [
        depth: socket.assigns.url_depth,
        index_graph: socket.assigns.url_index_graph
      ]

      opts =
        if socket.assigns.url_auth_token != "" do
          Keyword.put(opts, :auth_token, socket.assigns.url_auth_token)
        else
          opts
        end

      {:ok, task_pid} =
        Task.start(fn ->
          send(pid, {:progress, "Analyzing URL: #{url}..."})
          result = Analyze.analyze_url(url, opts)
          send(pid, {:url_analysis_complete, result})
        end)

      ref = Process.monitor(task_pid)

      {:noreply,
       assign(socket,
         running: true,
         task_pid: task_pid,
         task_ref: ref,
         error: nil,
         url_result: nil,
         progress: []
       )}
    end
  end

  def handle_event("cancel_analysis", _params, socket) do
    if pid = socket.assigns.task_pid do
      Process.exit(pid, :kill)
    end

    progress = socket.assigns.progress ++ ["Analysis cancelled by user"]
    {:noreply, assign(socket, running: false, task_pid: nil, progress: progress)}
  end

  @impl Phoenix.LiveView
  def handle_info({:rageg_profile_changed, profile}, socket) do
    path = (profile && profile.path) || ""
    {:noreply, assign(socket, project_path: path)}
  end

  def handle_info({:progress, msg}, socket) do
    progress = socket.assigns.progress ++ [msg]
    {:noreply, assign(socket, progress: progress)}
  end

  def handle_info({:analysis_complete, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(
       running: false,
       task_pid: nil,
       results: result.results,
       index_result: result.index,
       error: nil
     )}
  end

  def handle_info({:analysis_complete, {:error, reason}}, socket) do
    {:noreply, assign(socket, running: false, task_pid: nil, error: to_string(reason))}
  end

  def handle_info({:url_analysis_complete, {:ok, report}}, socket) do
    progress = socket.assigns.progress ++ ["URL Analysis finished successfully"]

    {:noreply,
     socket
     |> assign(
       running: false,
       task_pid: nil,
       url_result: report,
       progress: progress,
       error: nil
     )}
  end

  def handle_info({:url_analysis_complete, {:error, reason}}, socket) do
    {:noreply, assign(socket, running: false, task_pid: nil, error: to_string(reason))}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, socket) do
    {:noreply, socket}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :killed}, socket) do
    {:noreply, assign(socket, running: false, task_pid: nil)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, socket) do
    {:noreply,
     assign(socket,
       running: false,
       task_pid: nil,
       error: "Analysis process crashed: #{inspect(reason)}"
     )}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold">{gettext("Run Analysis")}</h1>
          <p class="text-sm text-base-content/60">
            {gettext("Index and analyze local project directories or remote URLs & Git repositories")}
          </p>
        </div>

        <%!-- Mode Selector --%>
        <div class="join bg-base-200 p-1 rounded-lg self-start">
          <button
            class={["join-item btn btn-sm border-none", @mode == :local && "btn-primary shadow-sm"]}
            phx-click="select_mode"
            phx-value-mode="local"
          >
            <.icon name="hero-folder-open" class="size-4" />
            {gettext("Local Directory")}
          </button>
          <button
            class={["join-item btn btn-sm border-none", @mode == :url && "btn-primary shadow-sm"]}
            phx-click="select_mode"
            phx-value-mode="url"
          >
            <.icon name="hero-globe-alt" class="size-4" />
            {gettext("URL / Remote Repo")}
          </button>
        </div>
      </div>

      <%= if @mode == :local do %>
        <%!-- Local Project path input --%>
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-4">
            <div class="form-control">
              <label class="label">
                <span class="label-text">{gettext("Project Path")}</span>
              </label>
              <div class="flex gap-2">
                <input
                  type="text"
                  name="path"
                  value={@project_path}
                  placeholder="/path/to/project"
                  class="input input-bordered flex-1 font-mono"
                  phx-change="update_path"
                  phx-debounce="300"
                  disabled={@running}
                />
                <button
                  class="btn btn-primary gap-2"
                  phx-click="run_analysis"
                  disabled={@running or @project_path == ""}
                >
                  <span :if={@running} class="loading loading-spinner loading-sm"></span>
                  <.icon :if={!@running} name="hero-play" class="size-5" />
                  {if @running, do: gettext("Running..."), else: gettext("Analyze")}
                </button>
              </div>
            </div>
          </div>
        </div>

        <%!-- Analysis type checkboxes --%>
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-4">
            <h2 class="card-title text-sm mb-2">{gettext("Analysis Types")}</h2>
            <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-2">
              <label
                :for={{key, label, _default} <- Analyze.analysis_types()}
                class="flex items-center gap-2 p-2 rounded-box bg-base-100 cursor-pointer hover:bg-base-300/50 transition-colors"
              >
                <input
                  type="checkbox"
                  class="checkbox checkbox-sm checkbox-primary"
                  checked={Map.get(@analyses, key, false)}
                  phx-click="toggle_analysis"
                  phx-value-key={key}
                  disabled={@running}
                />
                <span class="text-xs">{label}</span>
              </label>
            </div>
          </div>
        </div>
      <% else %>
        <%!-- URL / Remote Repository input --%>
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-4 space-y-4">
            <div class="form-control">
              <label class="label">
                <span class="label-text font-semibold">
                  {gettext("Target URL or Git Repository")}
                </span>
              </label>
              <div class="flex gap-2">
                <input
                  type="text"
                  name="url"
                  value={@url_input}
                  placeholder="https://github.com/owner/repo or web documentation URL"
                  class="input input-bordered flex-1 font-mono text-sm"
                  phx-change="update_url"
                  phx-debounce="300"
                  disabled={@running}
                />
                <button
                  class="btn btn-primary gap-2"
                  phx-click="run_url_analysis"
                  disabled={@running or @url_input == ""}
                >
                  <span :if={@running} class="loading loading-spinner loading-sm"></span>
                  <.icon :if={!@running} name="hero-cloud-arrow-down" class="size-5" />
                  {if @running, do: gettext("Analyzing..."), else: gettext("Analyze URL")}
                </button>
              </div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-3 gap-4 pt-2 border-t border-base-300">
              <div class="form-control">
                <label class="label py-1">
                  <span class="label-text text-xs">{gettext("Analysis Depth")}</span>
                </label>
                <select
                  class="select select-bordered select-sm"
                  name="depth"
                  phx-change="update_url_opts"
                  disabled={@running}
                >
                  <option value="shallow" selected={@url_depth == "shallow"}>
                    {gettext("Shallow (Quick Overview)")}
                  </option>
                  <option value="deep" selected={@url_depth == "deep"}>
                    {gettext("Deep (Full AST & Relations)")}
                  </option>
                </select>
              </div>

              <div class="form-control">
                <label class="label py-1">
                  <span class="label-text text-xs">{gettext("Auth Token (Optional)")}</span>
                </label>
                <input
                  type="password"
                  name="auth_token"
                  value={@url_auth_token}
                  placeholder="GitHub / GitLab Personal Token"
                  class="input input-bordered input-sm font-mono"
                  phx-change="update_url_opts"
                  disabled={@running}
                />
              </div>

              <div class="form-control justify-end">
                <label class="flex items-center gap-2 cursor-pointer py-2">
                  <input
                    type="checkbox"
                    name="index_graph"
                    value="true"
                    checked={@url_index_graph}
                    class="checkbox checkbox-sm checkbox-primary"
                    phx-change="update_url_opts"
                    disabled={@running}
                  />
                  <span class="text-xs font-medium">{gettext("Index into Knowledge Graph")}</span>
                </label>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Error --%>
      <div :if={@error} class="alert alert-error">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>{@error}</span>
      </div>

      <%!-- Progress --%>
      <div :if={@running} class="card bg-base-200 shadow-sm">
        <div class="card-body p-4">
          <div class="flex items-center justify-between">
            <h2 class="card-title text-sm gap-2">
              <span class="loading loading-spinner loading-sm text-primary"></span>
              {gettext("Progress")}
            </h2>
            <button
              class="btn btn-sm btn-error btn-outline gap-1"
              phx-click="cancel_analysis"
            >
              <.icon name="hero-x-mark" class="size-4" />
              {gettext("Cancel")}
            </button>
          </div>
          <ul class="mt-2 space-y-1">
            <li :for={msg <- @progress} class="text-xs text-base-content/70 flex items-center gap-2">
              <.icon name="hero-check" class="size-3 text-success" />
              {msg}
            </li>
          </ul>
        </div>
      </div>

      <%!-- Local Results --%>
      <div :if={@results && @mode == :local} class="space-y-4">
        <%!-- Index summary --%>
        <div :if={@index_result} class="card bg-base-200 shadow-sm">
          <div class="card-body p-4">
            <h2 class="card-title text-sm">{gettext("Indexing Results")}</h2>
            <div class="flex gap-4 mt-2">
              <div class="stat bg-base-100 rounded-box p-3">
                <div class="stat-title text-xs">{gettext("Files")}</div>
                <div class="stat-value text-lg">{@index_result.files_analyzed}</div>
              </div>
              <div class="stat bg-base-100 rounded-box p-3">
                <div class="stat-title text-xs">{gettext("Entities")}</div>
                <div class="stat-value text-lg">{@index_result.entities_found}</div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Analysis results --%>
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-4">
            <h2 class="card-title text-sm">{gettext("Analysis Results")}</h2>
            <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3 mt-3">
              <.result_card
                :for={{key, count, path} <- result_cards(@results)}
                label={to_string(key)}
                count={count}
                path={path}
              />
            </div>
          </div>
        </div>
      </div>

      <%!-- URL Analysis Result --%>
      <div :if={@url_result && @mode == :url} class="card bg-base-200 shadow-sm">
        <div class="card-body p-4 space-y-4">
          <div class="flex items-center justify-between border-b border-base-300 pb-3">
            <div>
              <h2 class="card-title text-base font-bold flex items-center gap-2">
                <.icon name="hero-check-circle" class="size-5 text-success" />
                {gettext("URL Analysis Report")}
              </h2>
              <p class="text-xs text-base-content/60 font-mono mt-0.5">{@url_input}</p>
            </div>
            <span class="badge badge-primary font-mono text-xs uppercase">
              {Map.get(@url_result, :target_type, Map.get(@url_result, "target_type", "analyzed"))}
            </span>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div class="stat bg-base-100 rounded-box p-3">
              <div class="stat-title text-xs">{gettext("Schema Format")}</div>
              <div class="stat-value text-sm font-mono">
                {Map.get(
                  @url_result,
                  :version,
                  Map.get(@url_result, "version", "ragex.url_analysis.v1")
                )}
              </div>
            </div>
            <div class="stat bg-base-100 rounded-box p-3">
              <div class="stat-title text-xs">{gettext("Indexed Status")}</div>
              <div class="stat-value text-sm font-semibold text-success">
                {if Map.get(@url_result, :indexed, Map.get(@url_result, "indexed", true)),
                  do: "Knowledge Graph Updated",
                  else: "Not Indexed"}
              </div>
            </div>
            <div class="stat bg-base-100 rounded-box p-3">
              <div class="stat-title text-xs">{gettext("Entities Extracted")}</div>
              <div class="stat-value text-lg">
                {extract_url_entity_count(@url_result)}
              </div>
            </div>
          </div>

          <%!-- Raw Report Details --%>
          <div>
            <h3 class="text-xs font-semibold uppercase text-base-content/60 mb-1">
              {gettext("Analysis Payload JSON")}
            </h3>
            <pre
              class="bg-base-300 p-3 rounded-lg font-mono text-xs overflow-x-auto max-h-96"
              phx-no-curly-interpolation
            ><%= Jason.encode!(@url_result, pretty: true) %></pre>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -- Components --

  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :path, :string, required: true

  defp result_card(assigns) do
    ~H"""
    <.link
      navigate={@path}
      class="stat bg-base-100 rounded-box p-3 hover:bg-base-300/50 transition-colors cursor-pointer"
    >
      <div class="stat-title text-xs capitalize">{String.replace(@label, "_", " ")}</div>
      <div class="stat-value text-lg">{@count}</div>
    </.link>
    """
  end

  # -- Helpers --

  defp result_cards(results) when is_map(results) do
    Enum.flat_map(results, fn {key, value} ->
      count = extract_count(value)
      path = analysis_link(key)
      [{key, count, path}]
    end)
    |> Enum.sort_by(fn {_, count, _} -> -count end)
  end

  defp result_cards(_), do: []

  defp extract_count(%{issues: issues}) when is_list(issues), do: length(issues)
  defp extract_count(%{smells: smells}) when is_list(smells), do: length(smells)
  defp extract_count(%{duplicates: dupes}) when is_list(dupes), do: length(dupes)
  defp extract_count(%{dead_functions: fns}) when is_list(fns), do: length(fns)
  defp extract_count(%{complex_functions: fns}) when is_list(fns), do: length(fns)
  defp extract_count(%{cycles: cycles}) when is_list(cycles), do: length(cycles)
  defp extract_count(%{modules: mods}) when is_list(mods), do: length(mods)
  defp extract_count(%{metrics: metrics}) when is_list(metrics), do: length(metrics)
  defp extract_count(%{results: results}) when is_list(results), do: length(results)
  defp extract_count(%{total_issues: n}) when is_integer(n), do: n
  defp extract_count(_), do: 0

  defp extract_url_entity_count(report) when is_map(report) do
    cond do
      is_integer(report[:entities_count]) -> report[:entities_count]
      is_integer(report["entities_count"]) -> report["entities_count"]
      is_list(report[:entities]) -> length(report[:entities])
      is_list(report["entities"]) -> length(report["entities"])
      is_map(report[:ast]) -> map_size(report[:ast])
      is_map(report["ast"]) -> map_size(report["ast"])
      true -> 1
    end
  end

  defp extract_url_entity_count(_), do: 0

  defp analysis_link(:security), do: ~p"/quality"
  defp analysis_link(:smells), do: ~p"/quality"
  defp analysis_link(:duplicates), do: ~p"/quality"
  defp analysis_link(:dead_code), do: ~p"/quality"
  defp analysis_link(:complexity), do: ~p"/quality"
  defp analysis_link(:business_logic), do: ~p"/quality"
  defp analysis_link(:dependencies), do: ~p"/dependencies"
  defp analysis_link(:circulars), do: ~p"/dependencies"
  defp analysis_link(:god_modules), do: ~p"/dependencies"
  defp analysis_link(:unstable_modules), do: ~p"/dependencies"
  defp analysis_link(:unused_modules), do: ~p"/dependencies"
  defp analysis_link(:coupling), do: ~p"/dependencies"
  defp analysis_link(_), do: ~p"/quality"
end
