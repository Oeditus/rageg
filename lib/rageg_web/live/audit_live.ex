defmodule RagegWeb.AuditLive do
  @moduledoc """
  Audit Report page -- AI-powered code audit with export.

  Features:
  - Run audit button triggering full analysis + AI report
  - Progress indicator during analysis
  - Markdown report viewer
  - Export as Markdown or JSON
  - Findings summary cards linking to Quality/Dependencies pages
  """

  use RagegWeb, :live_view

  alias Rageg.Chat

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Audit Report"))
     |> assign(current_path: "/audit")
     |> assign(project_path: "")
     |> assign(running: false)
     |> assign(report: nil)
     |> assign(summary: nil)
     |> assign(session_id: nil)
     |> assign(error: nil)
     |> assign(provider: :deepseek_r1)}
  end

  @impl Phoenix.LiveView
  def handle_event("update_path", %{"path" => path}, socket) do
    {:noreply, assign(socket, project_path: path)}
  end

  def handle_event("change_provider", %{"provider" => provider}, socket) do
    {:noreply, assign(socket, provider: String.to_existing_atom(provider))}
  end

  def handle_event("run_audit", _params, socket) do
    path = socket.assigns.project_path

    if path == "" do
      {:noreply, assign(socket, error: gettext("Enter a project path"))}
    else
      pid = self()

      Task.start(fn ->
        result = Chat.run_audit(path, provider: socket.assigns.provider)
        send(pid, {:audit_complete, result})
      end)

      {:noreply, assign(socket, running: true, error: nil, report: nil, summary: nil)}
    end
  end

  def handle_event("export_markdown", _params, socket) do
    if socket.assigns.report do
      {:noreply,
       push_event(socket, "download", %{
         filename: "audit-report.md",
         content: socket.assigns.report,
         mime: "text/markdown"
       })}
    else
      {:noreply, socket}
    end
  end

  def handle_event("export_json", _params, socket) do
    if socket.assigns.summary do
      json = Jason.encode!(socket.assigns.summary, pretty: true)

      {:noreply,
       push_event(socket, "download", %{
         filename: "audit-report.json",
         content: json,
         mime: "application/json"
       })}
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:audit_complete, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(
       running: false,
       report: result.report,
       summary: result[:summary] || result[:issues],
       session_id: result.session_id,
       error: nil
     )}
  end

  def handle_info({:audit_complete, {:error, reason}}, socket) do
    {:noreply, assign(socket, running: false, error: to_string(reason))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Header --%>
      <div>
        <h1 class="text-2xl font-bold">{gettext("Audit Report")}</h1>
        <p class="text-sm text-base-content/60">
          {gettext("AI-powered comprehensive code audit")}
        </p>
      </div>

      <%!-- Controls --%>
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body p-4">
          <div class="flex flex-wrap items-end gap-3">
            <div class="form-control flex-1 min-w-[200px]">
              <label class="label">
                <span class="label-text">{gettext("Project Path")}</span>
              </label>
              <input
                type="text"
                name="path"
                value={@project_path}
                placeholder="/path/to/project"
                class="input input-bordered"
                phx-change="update_path"
                phx-debounce="300"
                disabled={@running}
              />
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">{gettext("Provider")}</span>
              </label>
              <select
                class="select select-bordered"
                phx-change="change_provider"
                name="provider"
                disabled={@running}
              >
                <option
                  :for={{key, label} <- Chat.providers()}
                  value={key}
                  selected={key == @provider}
                >
                  {label}
                </option>
              </select>
            </div>

            <button
              class="btn btn-primary gap-2"
              phx-click="run_audit"
              disabled={@running or @project_path == ""}
            >
              <.icon :if={!@running} name="hero-play" class="size-5" />
              <span :if={@running} class="loading loading-spinner loading-sm"></span>
              {if @running, do: gettext("Analyzing..."), else: gettext("Run Audit")}
            </button>
          </div>
        </div>
      </div>

      <%!-- Error --%>
      <div :if={@error} class="alert alert-error">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>{@error}</span>
      </div>

      <%!-- Progress --%>
      <div :if={@running} class="flex flex-col items-center py-12">
        <span class="loading loading-spinner loading-lg text-primary"></span>
        <p class="mt-4 text-base-content/60">
          {gettext("Running analysis and generating report...")}
        </p>
        <p class="text-xs text-base-content/40 mt-1">{gettext("This may take a few minutes")}</p>
      </div>

      <%!-- Report --%>
      <div :if={@report} class="space-y-4">
        <%!-- Export buttons --%>
        <div class="flex gap-2 justify-end">
          <button class="btn btn-sm btn-ghost gap-1" phx-click="export_markdown">
            <.icon name="hero-arrow-down-tray" class="size-4" />
            {gettext("Export Markdown")}
          </button>
          <button :if={@summary} class="btn btn-sm btn-ghost gap-1" phx-click="export_json">
            <.icon name="hero-arrow-down-tray" class="size-4" />
            {gettext("Export JSON")}
          </button>
        </div>

        <%!-- Report content --%>
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-6 prose prose-sm max-w-none">
            <div class="whitespace-pre-wrap font-mono text-xs leading-relaxed">
              {@report}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
