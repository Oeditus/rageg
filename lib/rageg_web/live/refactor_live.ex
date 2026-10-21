defmodule RagegWeb.RefactorLive do
  @moduledoc """
  Visual Refactoring wizard -- operation picker, parameter forms, apply/rollback.

  Features:
  - Card grid of available refactoring operations
  - Dynamic parameter form based on selected operation
  - Execute refactoring with progress and result display
  - Rollback (undo) last operation
  """

  use RagegWeb, :live_view

  alias Rageg.Refactor
  alias Rageg.TaskRunner

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Refactoring"))
     |> assign(current_path: "/refactor")
     |> assign(selected_op: nil)
     |> assign(params: %{})
     |> assign(executing: false)
     |> assign(previewing: false)
     |> assign(preview_result: nil)
     |> assign(confirming: false)
     |> assign(result: nil)
     |> assign(job_tag: nil)
     |> assign(error: nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("select_operation", %{"op" => op}, socket) do
    op_atom = String.to_existing_atom(op)

    {:noreply,
     assign(socket,
       selected_op: op_atom,
       params: %{},
       result: nil,
       error: nil,
       preview_result: nil
     )}
  end

  def handle_event("back_to_picker", _params, socket) do
    {:noreply,
     assign(socket, selected_op: nil, params: %{}, result: nil, error: nil, preview_result: nil)}
  end

  def handle_event("update_params", params, socket) do
    # Merge form params (skip _target and _csrf). Keys that are not already
    # known atoms are ignored instead of creating new atoms from user input.
    new_params =
      params
      |> Map.drop(["_target", "_csrf_token"])
      |> Enum.reduce(%{}, fn {k, v}, acc ->
        case safe_key_atom(k) do
          nil -> acc
          atom -> Map.put(acc, atom, parse_param_value(v))
        end
      end)

    {:noreply,
     assign(socket, params: Map.merge(socket.assigns.params, new_params), preview_result: nil)}
  end

  def handle_event("execute", _params, socket) do
    op = socket.assigns.selected_op
    params = socket.assigns.params

    socket =
      TaskRunner.start(socket, :refactor_execute, fn -> Refactor.execute(op, params, []) end)

    {:noreply,
     assign(socket,
       executing: true,
       confirming: false,
       error: nil,
       result: nil,
       preview_result: nil
     )}
  end

  def handle_event("preview", _params, socket) do
    op = socket.assigns.selected_op
    params = socket.assigns.params

    socket =
      TaskRunner.start(socket, :refactor_preview, fn -> Refactor.preview(op, params, []) end)

    {:noreply, assign(socket, previewing: true, error: nil, preview_result: nil)}
  end

  # "Show diff -> confirm -> apply" workflow: the preview is the confirmation
  # step, so applying from a clean conflict analysis requires one extra click.
  def handle_event("request_apply", _params, socket) do
    case socket.assigns.preview_result do
      nil ->
        {:noreply, assign(socket, error: gettext("Generate a preview before applying"))}

      %{conflicts: %{stats: %{errors: errors}}} when errors > 0 ->
        {:noreply,
         assign(socket,
           error:
             gettext("Resolve the %{count} blocking conflict(s) before applying",
               count: errors
             )
         )}

      _ ->
        {:noreply, assign(socket, confirming: true, error: nil)}
    end
  end

  def handle_event("cancel_apply", _params, socket) do
    {:noreply, assign(socket, confirming: false)}
  end

  def handle_event("undo", _params, socket) do
    project_path = (socket.assigns.active_profile && socket.assigns.active_profile.path) || "."

    case Refactor.undo(project_path) do
      {:ok, result} ->
        {:noreply, assign(socket, result: {:undo, result}, error: nil, preview_result: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: to_string(reason))}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:rageg_profile_changed, _profile}, socket) do
    {:noreply, socket}
  end

  def handle_info({:task_result, :refactor_execute, {:ok, result}}, socket) do
    {:noreply, assign(socket, executing: false, job_tag: nil, result: {:ok, result})}
  end

  def handle_info({:task_result, :refactor_execute, {:error, reason}}, socket) do
    {:noreply, assign(socket, executing: false, job_tag: nil, error: to_string(reason))}
  end

  def handle_info({:task_result, :refactor_preview, {:ok, result}}, socket) do
    {:noreply, assign(socket, previewing: false, job_tag: nil, preview_result: result)}
  end

  def handle_info({:task_result, :refactor_preview, {:error, reason}}, socket) do
    {:noreply, assign(socket, previewing: false, job_tag: nil, error: to_string(reason))}
  end

  def handle_info({:task_error, tag, reason}, socket)
      when tag in [:refactor_execute, :refactor_preview] do
    {:noreply,
     assign(socket,
       executing: false,
       previewing: false,
       job_tag: nil,
       error: gettext("Refactoring failed: %{reason}", reason: inspect(reason))
     )}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">{gettext("Refactoring")}</h1>
          <p class="text-sm text-base-content/60">
            {gettext("Visual refactoring wizard with live preview")}
          </p>
        </div>
        <button class="btn btn-sm btn-ghost gap-1" phx-click="undo" title={gettext("Undo last")}>
          <.icon name="hero-arrow-uturn-left" class="size-4" />
          {gettext("Undo")}
        </button>
      </div>

      <%!-- Error --%>
      <div :if={@error} class="alert alert-error">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>{@error}</span>
      </div>

      <%!-- Result --%>
      <div :if={@result} class="alert alert-success">
        <.icon name="hero-check-circle" class="size-5" />
        <span>{format_result(@result)}</span>
      </div>

      <%!-- Operation picker (when no op selected) --%>
      <div :if={!@selected_op} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <button
          :for={{op, label, icon, desc} <- Refactor.operations()}
          class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow text-left cursor-pointer"
          phx-click="select_operation"
          phx-value-op={op}
        >
          <div class="card-body p-4">
            <h3 class="card-title text-sm">
              <.icon name={icon} class="size-5 text-primary" />
              {label}
            </h3>
            <p class="text-xs text-base-content/60">{desc}</p>
          </div>
        </button>
      </div>

      <%!-- Parameter form & Preview (when op selected) --%>
      <div :if={@selected_op} class="space-y-6">
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-6">
            <div class="flex items-center gap-2 mb-4">
              <button class="btn btn-sm btn-ghost" phx-click="back_to_picker">
                <.icon name="hero-arrow-left" class="size-4" />
              </button>
              <h2 class="text-lg font-bold">{op_label(@selected_op)}</h2>
            </div>

            <form phx-change="update_params" phx-submit="preview" class="space-y-4">
              <div
                :for={{field, label, type} <- Refactor.operation_fields(@selected_op)}
                class="form-control"
              >
                <label class="label">
                  <span class="label-text">{label}</span>
                </label>
                <input
                  type={type}
                  name={field}
                  value={Map.get(@params, field, "")}
                  class="input input-bordered"
                  required
                />
              </div>

              <div class="flex flex-wrap gap-2 mt-6">
                <button
                  id="refactor-preview-btn"
                  type="button"
                  class="btn btn-primary gap-2"
                  disabled={@executing or @previewing}
                  phx-click="preview"
                >
                  <span :if={@previewing} class="loading loading-spinner loading-sm"></span>
                  <.icon :if={!@previewing} name="hero-eye" class="size-5" />
                  {if @previewing, do: gettext("Simulating..."), else: gettext("Preview Changes")}
                </button>
                <button
                  id="refactor-apply-btn"
                  type="button"
                  class="btn btn-secondary gap-2"
                  disabled={@executing or @previewing or is_nil(@preview_result)}
                  phx-click="request_apply"
                  title={gettext("Preview the change first, then confirm")}
                >
                  <span :if={@executing} class="loading loading-spinner loading-sm"></span>
                  <.icon :if={!@executing} name="hero-check" class="size-5" />
                  {if @executing, do: gettext("Applying..."), else: gettext("Apply Changes")}
                </button>
                <button type="button" class="btn btn-ghost" phx-click="back_to_picker">
                  {gettext("Cancel")}
                </button>
              </div>
            </form>
          </div>
        </div>

        <%!-- Apply confirmation (after a clean preview) --%>
        <div
          :if={@confirming}
          id="refactor-confirm-overlay"
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
        >
          <div class="bg-base-100 rounded-2xl shadow-2xl p-6 w-full max-w-md mx-4 space-y-4">
            <h3 class="text-lg font-bold flex items-center gap-2">
              <.icon name="hero-exclamation-triangle" class="size-5 text-warning" />
              {gettext("Apply this refactoring?")}
            </h3>
            <p class="text-sm text-base-content/70">
              {gettext(
                "This will rewrite %{files} file(s) on disk. Use Undo if the result is not what you expected.",
                files: length(@preview_result.diffs)
              )}
            </p>
            <div class="bg-base-200 rounded-lg p-3 text-xs font-mono space-y-1 max-h-40 overflow-y-auto">
              <div :for={diff <- @preview_result.diffs} class="flex justify-between gap-2">
                <span class="truncate">{diff.file}</span>
                <span class="shrink-0">
                  <span class="text-success">+{diff.additions}</span>
                  <span class="text-error">-{diff.deletions}</span>
                </span>
              </div>
            </div>
            <div class="flex justify-end gap-3">
              <button
                id="refactor-confirm-cancel"
                phx-click="cancel_apply"
                class="btn btn-ghost btn-sm"
              >
                {gettext("Cancel")}
              </button>
              <button
                id="refactor-confirm-run"
                phx-click="execute"
                class="btn btn-error btn-sm gap-1"
              >
                <.icon name="hero-check" class="size-4" />
                {gettext("Yes, apply")}
              </button>
            </div>
          </div>
        </div>

        <%!-- Dry-Run Preview Results --%>
        <div :if={@preview_result} class="space-y-4">
          <h2 class="text-lg font-bold">{gettext("Refactoring Simulation Preview")}</h2>

          <%!-- Conflict checks --%>
          <div
            :if={@preview_result.conflicts.has_conflicts}
            class="card bg-base-200 shadow-sm border-l-4 border-error/50"
          >
            <div class="card-body p-4 space-y-3">
              <h3 class="font-semibold text-sm flex items-center gap-2 text-error">
                <.icon name="hero-exclamation-triangle" class="size-5" />
                {gettext("Conflicts Detected")}
                <span class="badge badge-error badge-sm">
                  {@preview_result.conflicts.stats.errors} {gettext("errors")}
                </span>
                <span class="badge badge-warning badge-sm">
                  {@preview_result.conflicts.stats.warnings} {gettext("warnings")}
                </span>
              </h3>
              <div class="space-y-2">
                <div
                  :for={c <- @preview_result.conflicts.conflicts}
                  class={[
                    "p-2 rounded bg-base-100 text-xs border",
                    if(c.severity == :error,
                      do: "border-error/20 text-error",
                      else: "border-warning/20 text-warning"
                    )
                  ]}
                >
                  <div class="font-bold capitalize">{c.severity}: {c.message}</div>
                  <div :if={c.file} class="opacity-70 mt-1 font-mono">{c.file} : {c.line}</div>
                  <div :if={c.suggestion} class="italic mt-1 text-base-content/80">
                    Suggestion: {c.suggestion}
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div :if={!@preview_result.conflicts.has_conflicts} class="alert alert-success text-xs">
            <.icon name="hero-check-circle" class="size-5" />
            <span>
              {gettext("Conflict analysis clean: no arity, name or scope issues detected.")}
            </span>
          </div>

          <%!-- Diffs --%>
          <div class="space-y-4">
            <div :for={diff <- @preview_result.diffs} class="space-y-1">
              <div class="flex items-center justify-between px-2 text-xs">
                <span class="font-mono font-bold break-all text-base-content/70">{diff.file}</span>
                <span class="flex gap-2">
                  <span class="text-success font-semibold">+{diff.additions}</span>
                  <span class="text-error font-semibold">-{diff.deletions}</span>
                </span>
              </div>
              <div class="overflow-x-auto rounded-box bg-base-300">
                {raw(diff.html)}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -- Helpers --

  defp op_label(op) do
    Refactor.operations()
    |> Enum.find_value(fn {key, label, _, _} -> if key == op, do: label end)
  end

  defp format_result({:ok, %{files_modified: n}}),
    do: "Refactoring completed: #{n} files modified"

  defp format_result({:ok, result}), do: "Refactoring completed: #{inspect(result)}"
  defp format_result({:undo, %{files_restored: n}}), do: "Undo completed: #{n} files restored"
  defp format_result({:undo, result}), do: "Undo completed: #{inspect(result)}"
  defp format_result(_), do: "Operation completed"

  defp parse_param_value(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} -> int
      _ -> val
    end
  end

  defp parse_param_value(val), do: val

  defp safe_key_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
