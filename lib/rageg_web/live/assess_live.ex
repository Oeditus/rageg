defmodule RagegWeb.AssessLive do
  @moduledoc """
  PR / Branch Assessment page.

  Allows the user to select a head branch and base ref, then runs
  the Ragex assessment pipeline (static analysis + AI code review)
  with real-time progress updates. The resulting Markdown report
  is rendered inline.
  """

  use RagegWeb, :live_view

  alias Rageg.Assess

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    active_path =
      case Rageg.Profiles.active() do
        %{path: p} -> p
        _ -> ""
      end

    branches =
      if active_path != "" do
        case Assess.list_branches(active_path) do
          {:ok, list} -> list
          _ -> []
        end
      else
        []
      end

    current_branch =
      case Enum.find(branches, & &1.current?) do
        %{name: name} -> name
        _ -> ""
      end

    {:ok,
     socket
     |> assign(page_title: gettext("PR Assessment"))
     |> assign(current_path: "/assess")
     |> assign(project_path: active_path)
     |> assign(branches: branches)
     |> assign(head_branch: current_branch)
     |> assign(base_ref: "origin/main")
     |> assign(format: "markdown")
     |> assign(running: false)
     |> assign(task_pid: nil)
     |> assign(progress: [])
     |> assign(report: nil)
     |> assign(result: nil)
     |> assign(error: nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("update_base", %{"base" => base}, socket) do
    {:noreply, assign(socket, base_ref: base)}
  end

  def handle_event("select_head", %{"head" => head}, socket) do
    {:noreply, assign(socket, head_branch: head)}
  end

  def handle_event("select_format", %{"format" => format}, socket) do
    {:noreply, assign(socket, format: format)}
  end

  def handle_event("refresh_branches", _params, socket) do
    path = socket.assigns.project_path

    branches =
      case Assess.list_branches(path) do
        {:ok, list} -> list
        _ -> []
      end

    {:noreply, assign(socket, branches: branches)}
  end

  def handle_event("run_assessment", _params, socket) do
    path = socket.assigns.project_path
    base = socket.assigns.base_ref
    head = socket.assigns.head_branch
    format = socket.assigns.format

    cond do
      path == "" ->
        {:noreply, assign(socket, error: gettext("No active project. Select a profile first."))}

      head == "" ->
        {:noreply, assign(socket, error: gettext("Select a branch to assess."))}

      true ->
        pid = self()

        {:ok, task_pid} =
          Task.start(fn ->
            result =
              Assess.run(path,
                base: base,
                head: head,
                format: format,
                on_progress: fn msg -> send(pid, {:progress, msg}) end
              )

            send(pid, {:assess_complete, result})
          end)

        ref = Process.monitor(task_pid)

        {:noreply,
         assign(socket,
           running: true,
           task_pid: task_pid,
           task_ref: ref,
           error: nil,
           report: nil,
           result: nil,
           progress: []
         )}
    end
  end

  def handle_event("cancel_assessment", _params, socket) do
    if pid = socket.assigns.task_pid do
      Process.exit(pid, :kill)
    end

    progress = socket.assigns.progress ++ ["Assessment cancelled by user"]
    {:noreply, assign(socket, running: false, task_pid: nil, progress: progress)}
  end

  @impl Phoenix.LiveView
  def handle_info({:rageg_profile_changed, profile}, socket) do
    path = (profile && profile.path) || ""

    branches =
      if path != "" do
        case Assess.list_branches(path) do
          {:ok, list} -> list
          _ -> []
        end
      else
        []
      end

    current_branch =
      case Enum.find(branches, & &1.current?) do
        %{name: name} -> name
        _ -> ""
      end

    {:noreply,
     assign(socket,
       project_path: path,
       branches: branches,
       head_branch: current_branch
     )}
  end

  def handle_info({:progress, msg}, socket) do
    progress = socket.assigns.progress ++ [msg]
    {:noreply, assign(socket, progress: progress)}
  end

  def handle_info({:assess_complete, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(
       running: false,
       task_pid: nil,
       report: result.report,
       result: result,
       error: nil
     )}
  end

  def handle_info({:assess_complete, {:error, reason}}, socket) do
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
       error: "Assessment process crashed: #{inspect(reason)}"
     )}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold">{gettext("PR / Branch Assessment")}</h1>
        <p class="text-sm text-base-content/60">
          {gettext("Evaluate a branch or PR using static analysis and AI-powered code review.")}
        </p>
      </div>

      <%!-- Branch Selection Card --%>
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body p-4 space-y-4">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <%!-- Base Ref --%>
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">{gettext("Base Ref")}</span>
              </label>
              <input
                type="text"
                name="base"
                id="assess-base-ref"
                value={@base_ref}
                placeholder="origin/main"
                class="input input-bordered font-mono"
                phx-change="update_base"
                phx-debounce="300"
                disabled={@running}
              />
              <span class="text-xs text-base-content/50 mt-1">
                {gettext("The base branch or git ref to diff against.")}
              </span>
            </div>

            <%!-- Head Branch Select --%>
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">{gettext("Head Branch")}</span>
              </label>
              <div class="flex gap-2">
                <select
                  name="head"
                  id="assess-head-branch"
                  class="select select-bordered flex-1 font-mono"
                  phx-change="select_head"
                  disabled={@running}
                >
                  <option value="" disabled selected={@head_branch == ""}>
                    {gettext("Select a branch...")}
                  </option>
                  <%= for branch <- @branches do %>
                    <option value={branch.name} selected={branch.name == @head_branch}>
                      {branch.name}{if branch.current?, do: " ★", else: ""}
                    </option>
                  <% end %>
                </select>
                <button
                  type="button"
                  class="btn btn-ghost btn-square"
                  phx-click="refresh_branches"
                  disabled={@running}
                  title={gettext("Refresh branches")}
                >
                  <.icon name="hero-arrow-path" class="size-4" />
                </button>
              </div>
              <span class="text-xs text-base-content/50 mt-1">
                {gettext("The branch or PR to assess. ★ = current branch.")}
              </span>
            </div>
          </div>

          <%!-- Format selector + Run button --%>
          <div class="flex items-end gap-3 pt-2 border-t border-base-300">
            <div class="form-control">
              <label class="label">
                <span class="label-text text-sm">{gettext("Output Format")}</span>
              </label>
              <select
                name="format"
                id="assess-format"
                class="select select-bordered select-sm"
                phx-change="select_format"
                disabled={@running}
              >
                <option value="markdown" selected={@format == "markdown"}>
                  {gettext("Markdown (AI Report)")}
                </option>
                <option value="json" selected={@format == "json"}>
                  {gettext("JSON (Structured Data)")}
                </option>
              </select>
            </div>
            <div class="flex-1"></div>
            <button
              id="assess-run-btn"
              class="btn btn-primary gap-2"
              phx-click="run_assessment"
              disabled={@running or @head_branch == "" or @project_path == ""}
            >
              <span :if={@running} class="loading loading-spinner loading-sm"></span>
              <.icon :if={!@running} name="hero-magnifying-glass-circle" class="size-5" />
              {if @running, do: gettext("Assessing..."), else: gettext("Run Assessment")}
            </button>
          </div>
        </div>
      </div>

      <%!-- Error --%>
      <div :if={@error} class="alert alert-error" id="assess-error">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>{@error}</span>
      </div>

      <%!-- Progress --%>
      <div :if={@running} class="card bg-base-200 shadow-sm" id="assess-progress">
        <div class="card-body p-4">
          <div class="flex items-center justify-between">
            <h2 class="card-title text-sm gap-2">
              <span class="loading loading-spinner loading-sm text-primary"></span>
              {gettext("Assessment Progress")}
            </h2>
            <button
              class="btn btn-sm btn-error btn-outline gap-1"
              phx-click="cancel_assessment"
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

      <%!-- Results --%>
      <div :if={@result} class="space-y-4" id="assess-results">
        <%!-- Summary card --%>
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-4">
            <h2 class="card-title text-sm flex items-center gap-2">
              <.icon name="hero-document-text" class="size-5 text-primary" />
              {gettext("Assessment Summary")}
            </h2>
            <div class="flex flex-wrap gap-3 mt-3">
              <div class="stat bg-base-100 rounded-box p-3 min-w-[100px]">
                <div class="stat-title text-xs">{gettext("Base")}</div>
                <div class="stat-value text-sm font-mono">{@result.base}</div>
              </div>
              <div class="stat bg-base-100 rounded-box p-3 min-w-[100px]">
                <div class="stat-title text-xs">{gettext("Head")}</div>
                <div class="stat-value text-sm font-mono">{@result.head}</div>
              </div>
              <div class="stat bg-base-100 rounded-box p-3 min-w-[100px]">
                <div class="stat-title text-xs">{gettext("Files Changed")}</div>
                <div class="stat-value text-lg">{length(@result.changed_files)}</div>
              </div>
              <div class="stat bg-base-100 rounded-box p-3 min-w-[100px]">
                <div class="stat-title text-xs">{gettext("Issues Found")}</div>
                <div class={[
                  "stat-value text-lg",
                  if(@result.summary[:total_issues] > 0, do: "text-warning", else: "text-success")
                ]}>
                  {Map.get(@result.summary, :total_issues, 0)}
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Changed files list --%>
        <div :if={@result.changed_files != []} class="card bg-base-200 shadow-sm">
          <div class="card-body p-4">
            <details class="collapse collapse-arrow">
              <summary class="collapse-title text-sm font-medium p-0 min-h-0">
                <.icon name="hero-document-duplicate" class="size-4 text-primary inline mr-1" />
                {gettext("Changed Files")} ({length(@result.changed_files)})
              </summary>
              <div class="collapse-content p-0 pt-2">
                <ul class="space-y-0.5">
                  <li :for={file <- @result.changed_files} class="text-xs font-mono text-base-content/70 py-0.5">
                    {file}
                  </li>
                </ul>
              </div>
            </details>
          </div>
        </div>

        <%!-- Report --%>
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-4">
            <h2 class="card-title text-sm flex items-center gap-2">
              <.icon name="hero-academic-cap" class="size-5 text-primary" />
              {gettext("Assessment Report")}
            </h2>
            <%= if @result.format == "json" do %>
              <pre class="mt-3 p-4 bg-base-100 rounded-box text-xs font-mono overflow-x-auto max-h-[70vh] overflow-y-auto whitespace-pre-wrap" phx-no-curly-interpolation>{@report}</pre>
            <% else %>
              <div class="mt-3 prose prose-sm max-w-none bg-base-100 rounded-box p-4 overflow-y-auto max-h-[70vh]">
                {raw(render_markdown(@report))}
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -- Helpers --

  defp render_markdown(nil), do: ""

  defp render_markdown(markdown) do
    MDEx.to_html!(markdown)
  rescue
    _ ->
      markdown
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()
  end
end
