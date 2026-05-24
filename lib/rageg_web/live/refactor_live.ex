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

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Refactoring"))
     |> assign(current_path: "/refactor")
     |> assign(selected_op: nil)
     |> assign(params: %{})
     |> assign(executing: false)
     |> assign(result: nil)
     |> assign(error: nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("select_operation", %{"op" => op}, socket) do
    op_atom = String.to_existing_atom(op)
    {:noreply, assign(socket, selected_op: op_atom, params: %{}, result: nil, error: nil)}
  end

  def handle_event("back_to_picker", _params, socket) do
    {:noreply, assign(socket, selected_op: nil, params: %{}, result: nil, error: nil)}
  end

  def handle_event("update_params", params, socket) do
    # Merge form params (skip _target and _csrf)
    new_params =
      params
      |> Map.drop(["_target", "_csrf_token"])
      |> Map.new(fn {k, v} -> {String.to_atom(k), parse_param_value(v)} end)

    {:noreply, assign(socket, params: Map.merge(socket.assigns.params, new_params))}
  end

  def handle_event("execute", _params, socket) do
    op = socket.assigns.selected_op
    params = socket.assigns.params
    pid = self()

    Task.start(fn ->
      result = Refactor.execute(op, params, [])
      send(pid, {:refactor_result, result})
    end)

    {:noreply, assign(socket, executing: true, error: nil, result: nil)}
  end

  def handle_event("undo", _params, socket) do
    case Refactor.undo(".") do
      {:ok, result} ->
        {:noreply, assign(socket, result: {:undo, result}, error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: to_string(reason))}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:refactor_result, {:ok, result}}, socket) do
    {:noreply, assign(socket, executing: false, result: {:ok, result})}
  end

  def handle_info({:refactor_result, {:error, reason}}, socket) do
    {:noreply, assign(socket, executing: false, error: to_string(reason))}
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

      <%!-- Parameter form (when op selected) --%>
      <div :if={@selected_op} class="card bg-base-200 shadow-sm">
        <div class="card-body p-6">
          <div class="flex items-center gap-2 mb-4">
            <button class="btn btn-sm btn-ghost" phx-click="back_to_picker">
              <.icon name="hero-arrow-left" class="size-4" />
            </button>
            <h2 class="text-lg font-bold">{op_label(@selected_op)}</h2>
          </div>

          <form phx-change="update_params" phx-submit="execute" class="space-y-4">
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

            <div class="flex gap-2 mt-6">
              <button
                type="submit"
                class="btn btn-primary gap-2"
                disabled={@executing}
              >
                <span :if={@executing} class="loading loading-spinner loading-sm"></span>
                <.icon :if={!@executing} name="hero-play" class="size-5" />
                {if @executing, do: gettext("Executing..."), else: gettext("Apply")}
              </button>
              <button type="button" class="btn btn-ghost" phx-click="back_to_picker">
                {gettext("Cancel")}
              </button>
            </div>
          </form>
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
end
