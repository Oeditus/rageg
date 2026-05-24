defmodule RagegWeb.AnalyzeLive do
  @moduledoc """
  Analysis Runner page -- configure and run Ragex analysis pipeline.

  Features:
  - Project directory input
  - Analysis type checkboxes (13 types with defaults)
  - Progress messages during indexing and analysis
  - Results summary with issue counts and links to detail pages
  """

  use RagegWeb, :live_view

  alias Rageg.Analyze

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    analyses = Analyze.default_analyses()

    {:ok,
     socket
     |> assign(page_title: gettext("Run Analysis"))
     |> assign(current_path: "/analyze")
     |> assign(project_path: "")
     |> assign(analyses: analyses)
     |> assign(running: false)
     |> assign(progress: [])
     |> assign(results: nil)
     |> assign(index_result: nil)
     |> assign(error: nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("update_path", %{"path" => path}, socket) do
    {:noreply, assign(socket, project_path: path)}
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

      Task.start(fn ->
        result =
          Analyze.run(path,
            analyses: analyses,
            on_progress: fn msg -> send(pid, {:progress, msg}) end
          )

        send(pid, {:analysis_complete, result})
      end)

      {:noreply, assign(socket, running: true, error: nil, results: nil, progress: [])}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:progress, msg}, socket) do
    progress = socket.assigns.progress ++ [msg]
    {:noreply, assign(socket, progress: progress)}
  end

  def handle_info({:analysis_complete, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(
       running: false,
       results: result.results,
       index_result: result.index,
       error: nil
     )}
  end

  def handle_info({:analysis_complete, {:error, reason}}, socket) do
    {:noreply, assign(socket, running: false, error: to_string(reason))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold">{gettext("Run Analysis")}</h1>
        <p class="text-sm text-base-content/60">{gettext("Index and analyze a project directory")}</p>
      </div>

      <%!-- Project path input --%>
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

      <%!-- Error --%>
      <div :if={@error} class="alert alert-error">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>{@error}</span>
      </div>

      <%!-- Progress --%>
      <div :if={@running} class="card bg-base-200 shadow-sm">
        <div class="card-body p-4">
          <h2 class="card-title text-sm gap-2">
            <span class="loading loading-spinner loading-sm text-primary"></span>
            {gettext("Progress")}
          </h2>
          <ul class="mt-2 space-y-1">
            <li :for={msg <- @progress} class="text-xs text-base-content/70 flex items-center gap-2">
              <.icon name="hero-check" class="size-3 text-success" />
              {msg}
            </li>
          </ul>
        </div>
      </div>

      <%!-- Results --%>
      <div :if={@results} class="space-y-4">
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
