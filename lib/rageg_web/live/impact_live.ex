defmodule RagegWeb.ImpactLive do
  @moduledoc """
  Impact Analysis page -- "What if" explorer for code changes.

  Features:
  - Target function/module input
  - Risk score gauge with color bands
  - Effort estimation table for all refactoring operations
  - Direct callers and affected functions list
  - Affected tests discovery
  - Recommendations
  """

  use RagegWeb, :live_view

  alias Rageg.Impact

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Impact Analysis"))
     |> assign(current_path: "/impact")
     |> assign(target: "")
     |> assign(loading: false)
     |> assign(analysis: nil)
     |> assign(risk: nil)
     |> assign(affected_tests: nil)
     |> assign(error: nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("update_target", %{"target" => target}, socket) do
    {:noreply, assign(socket, target: target)}
  end

  def handle_event("analyze", _params, socket) do
    target = socket.assigns.target

    if target == "" do
      {:noreply, assign(socket, error: gettext("Enter a target (e.g. MyModule.func/2)"))}
    else
      pid = self()

      Task.start(fn ->
        analysis = Impact.analyze_change(target)
        risk = Impact.risk_score(target)
        tests = Impact.find_affected_tests(target)
        send(pid, {:impact_results, analysis, risk, tests})
      end)

      {:noreply, assign(socket, loading: true, error: nil, analysis: nil, risk: nil)}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:impact_results, analysis, risk, tests}, socket) do
    analysis_data =
      case analysis do
        {:ok, a} -> a
        _ -> nil
      end

    risk_data =
      case risk do
        {:ok, r} -> r
        _ -> nil
      end

    tests_data =
      case tests do
        {:ok, t} -> t
        _ -> []
      end

    error =
      if is_nil(analysis_data) and is_nil(risk_data),
        do: gettext("Could not analyze target. Ensure the graph is populated."),
        else: nil

    {:noreply,
     socket
     |> assign(
       loading: false,
       analysis: analysis_data,
       risk: risk_data,
       affected_tests: tests_data,
       error: error
     )}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Header --%>
      <div>
        <h1 class="text-2xl font-bold">{gettext("Impact Analysis")}</h1>
        <p class="text-sm text-base-content/60">{gettext("Predict the impact of code changes")}</p>
      </div>

      <%!-- Target input --%>
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body p-4">
          <form phx-submit="analyze" phx-change="update_target" class="flex gap-3 items-end">
            <div class="form-control flex-1">
              <label class="label">
                <span class="label-text">{gettext("Target function or module")}</span>
              </label>
              <input
                type="text"
                name="target"
                value={@target}
                placeholder="MyModule.function/2"
                class="input input-bordered font-mono"
                disabled={@loading}
              />
            </div>
            <button class="btn btn-primary gap-2" type="submit" disabled={@loading or @target == ""}>
              <span :if={@loading} class="loading loading-spinner loading-sm"></span>
              <.icon :if={!@loading} name="hero-bolt" class="size-5" />
              {gettext("Analyze")}
            </button>
          </form>
        </div>
      </div>

      <%!-- Error --%>
      <div :if={@error} class="alert alert-warning">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>{@error}</span>
      </div>

      <%!-- Results --%>
      <div :if={@analysis || @risk} class="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <%!-- Risk gauge --%>
        <div :if={@risk} class="card bg-base-200 shadow-sm">
          <div class="card-body p-4 text-center">
            <h3 class="text-sm font-semibold mb-2">{gettext("Risk Score")}</h3>
            <div
              class={"radial-progress text-#{risk_color(@risk.level)}"}
              style={"--value:#{round(@risk.overall * 100)}; --size:8rem; --thickness:0.5rem;"}
              role="progressbar"
            >
              <span class="text-2xl font-bold">{round(@risk.overall * 100)}%</span>
            </div>
            <span class={"badge badge-#{risk_color(@risk.level)} mt-2"}>{@risk.level}</span>

            <div class="grid grid-cols-3 gap-2 mt-4 text-xs">
              <div>
                <div class="font-semibold">{gettext("Importance")}</div>
                <div>{@risk.importance}</div>
              </div>
              <div>
                <div class="font-semibold">{gettext("Coupling")}</div>
                <div>{@risk.coupling}</div>
              </div>
              <div>
                <div class="font-semibold">{gettext("Complexity")}</div>
                <div>{@risk.complexity}</div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Impact summary --%>
        <div :if={@analysis} class="card bg-base-200 shadow-sm lg:col-span-2">
          <div class="card-body p-4">
            <h3 class="text-sm font-semibold mb-3">{gettext("Impact Summary")}</h3>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
              <div class="stat bg-base-100 rounded-box p-3">
                <div class="stat-title text-xs">{gettext("Affected")}</div>
                <div class="stat-value text-lg">{@analysis.affected_count}</div>
              </div>
              <div class="stat bg-base-100 rounded-box p-3">
                <div class="stat-title text-xs">{gettext("Direct Callers")}</div>
                <div class="stat-value text-lg">{length(@analysis.direct_callers)}</div>
              </div>
              <div class="stat bg-base-100 rounded-box p-3">
                <div class="stat-title text-xs">{gettext("Depth")}</div>
                <div class="stat-value text-lg">{@analysis.depth}</div>
              </div>
              <div class="stat bg-base-100 rounded-box p-3">
                <div class="stat-title text-xs">{gettext("Tests Affected")}</div>
                <div class="stat-value text-lg">{length(@affected_tests || [])}</div>
              </div>
            </div>

            <%!-- Recommendations --%>
            <div :if={@analysis.recommendations != []} class="mt-4">
              <h4 class="text-xs font-semibold mb-2">{gettext("Recommendations")}</h4>
              <ul class="text-xs space-y-1">
                <li :for={rec <- @analysis.recommendations} class="flex gap-2">
                  <.icon name="hero-light-bulb" class="size-4 text-warning shrink-0 mt-0.5" />
                  <span class="text-base-content/70">{rec}</span>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </div>

      <%!-- Callers and affected --%>
      <div :if={@analysis} class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-4">
            <h3 class="text-sm font-semibold mb-2">
              {gettext("Direct Callers")} ({length(@analysis.direct_callers)})
            </h3>
            <div :if={@analysis.direct_callers == []} class="text-xs text-base-content/50">
              {gettext("No direct callers found")}
            </div>
            <ul class="text-xs space-y-1 max-h-48 overflow-y-auto font-mono">
              <li :for={caller <- @analysis.direct_callers} class="truncate text-base-content/70">
                {caller}
              </li>
            </ul>
          </div>
        </div>

        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-4">
            <h3 class="text-sm font-semibold mb-2">
              {gettext("Affected Tests")} ({length(@affected_tests || [])})
            </h3>
            <div :if={(@affected_tests || []) == []} class="text-xs text-base-content/50">
              {gettext("No affected tests found")}
            </div>
            <ul class="text-xs space-y-1 max-h-48 overflow-y-auto font-mono">
              <li :for={test <- @affected_tests || []} class="truncate text-base-content/70">
                {test}
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -- Helpers --

  defp risk_color(:critical), do: "error"
  defp risk_color(:high), do: "warning"
  defp risk_color(:medium), do: "info"
  defp risk_color(_), do: "success"
end
