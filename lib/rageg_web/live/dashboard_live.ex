defmodule RagegWeb.DashboardLive do
  @moduledoc """
  Real-time dashboard showing live statistics from Ragex and dllb.

  Displays five stat card groups:

  - **Knowledge Graph** -- node count, edge count, density, connected components
  - **Embeddings** -- model name, dimensions, total embeddings
  - **AI Cache** -- hit rate, misses, evictions, cache size
  - **AI Usage** -- total requests, tokens consumed, estimated cost
  - **dllb** -- connection status, pool size, latency

  All cards auto-refresh via PubSub broadcasts from `Rageg.Stats`.
  """

  use RagegWeb, :live_view

  alias Rageg.Stats

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Rageg.PubSub, Stats.topic())
    end

    stats = Stats.current()

    {:ok,
     socket
     |> assign(page_title: gettext("Dashboard"))
     |> assign(current_path: "/")
     |> assign(stats: stats)
     |> assign(reset_confirming: false)
     |> assign(reset_running: false)}
  end

  @impl Phoenix.LiveView
  def handle_info({:stats_updated, stats}, socket) do
    {:noreply, assign(socket, stats: stats)}
  end

  def handle_info({:rageg_profile_changed, _profile}, socket) do
    # Stats auto-refresh via the existing PubSub poller; nothing extra needed.
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("show_reset_confirm", _params, socket) do
    {:noreply, assign(socket, reset_confirming: true)}
  end

  @impl Phoenix.LiveView
  def handle_event("cancel_reset", _params, socket) do
    {:noreply, assign(socket, reset_confirming: false)}
  end

  @impl Phoenix.LiveView
  def handle_event("confirm_reset", _params, socket) do
    socket = assign(socket, reset_running: true, reset_confirming: false)

    # Clear dllb tables and the stats JSON file.
    Rageg.Dllb.clear_all!()

    # Clear the Ragex in-memory graph, vector store, AI cache, and usage.
    safe_clear(fn -> Ragex.Graph.Store.clear() end)
    safe_clear(fn -> Ragex.AI.Cache.clear() end)
    safe_clear(fn -> Ragex.Embeddings.Persistence.clear(:all) end)
    safe_clear(fn -> Ragex.Analysis.Quality.clear_all() end)
    safe_clear(fn -> Ragex.AI.Usage.reset_stats() end)

    # Apply the empty snapshot immediately so the counters reset in the UI
    # without waiting for the next background poll.
    {:noreply,
     socket
     |> assign(reset_running: false)
     |> assign(stats: Stats.empty_snapshot())}
  end

  defp safe_clear(fun) do
    fun.()
  rescue
    _ -> :ok
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Reset confirmation overlay --%>
      <%= if @reset_confirming do %>
        <div
          id="reset-confirm-overlay"
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
        >
          <div class="bg-base-100 rounded-2xl shadow-2xl p-6 w-full max-w-sm mx-4">
            <h3 class="text-lg font-bold text-error mb-2">
              {gettext("Reset All State?")}
            </h3>
            <p class="text-sm text-base-content/70 mb-6">
              {gettext(
                "This will permanently delete all ingested nodes, edges, embeddings, AI cache, and usage data. The dashboard will reset to zero."
              )}
            </p>
            <div class="flex gap-3 justify-end">
              <button
                id="reset-cancel-btn"
                phx-click="cancel_reset"
                class="px-4 py-2 rounded-lg text-sm font-medium bg-base-200 hover:bg-base-300 transition-colors"
              >
                {gettext("Cancel")}
              </button>
              <button
                id="reset-confirm-btn"
                phx-click="confirm_reset"
                class="px-4 py-2 rounded-lg text-sm font-medium bg-error text-error-content hover:bg-error/90 transition-colors"
              >
                {gettext("Yes, Reset Everything")}
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Header --%>
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">{gettext("Dashboard")}</h1>
          <p class="text-sm text-base-content/60">
            {gettext("Real-time statistics from Ragex and dllb")}
          </p>
        </div>
        <div class="flex items-center gap-3">
          <div class="badge badge-outline badge-sm">
            {gettext("Updated")} {Calendar.strftime(@stats.fetched_at, "%H:%M:%S")}
          </div>
          <button
            id="reset-state-btn"
            phx-click="show_reset_confirm"
            disabled={@reset_running}
            class={[
              "flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-colors",
              "bg-error/10 text-error hover:bg-error/20 border border-error/20",
              @reset_running && "opacity-50 cursor-not-allowed"
            ]}
          >
            <.icon name="hero-trash" class="size-3.5" />
            {if @reset_running, do: gettext("Resetting..."), else: gettext("Reset State")}
          </button>
        </div>
      </div>

      <%!-- Knowledge Graph Stats --%>
      <.stat_section
        title={gettext("Knowledge Graph")}
        icon="hero-share"
        color="primary"
      >
        <.stat_card label={gettext("Nodes")} value={format_number(@stats.graph.nodes)} />
        <.stat_card label={gettext("Edges")} value={format_number(@stats.graph.edges)} />
        <.stat_card label={gettext("Density")} value={format_float(@stats.graph.density)} />
        <.stat_card label={gettext("Components")} value={format_number(@stats.graph.components)} />
      </.stat_section>

      <%!-- Embeddings Stats --%>
      <.stat_section
        title={gettext("Embeddings")}
        icon="hero-sparkles"
        color="secondary"
      >
        <.stat_card label={gettext("Model")} value={@stats.embeddings.model} />
        <.stat_card label={gettext("Dimensions")} value={format_number(@stats.embeddings.dimensions)} />
        <.stat_card label={gettext("Total Vectors")} value={format_number(@stats.embeddings.total)} />
      </.stat_section>

      <%!-- AI Cache Stats --%>
      <.stat_section
        title={gettext("AI Cache")}
        icon="hero-archive-box"
        color="accent"
      >
        <.stat_card label={gettext("Hit Rate")} value={format_percent(@stats.cache.hit_rate)} />
        <.stat_card label={gettext("Misses")} value={format_number(@stats.cache.misses)} />
        <.stat_card label={gettext("Evictions")} value={format_number(@stats.cache.evictions)} />
        <.stat_card label={gettext("Cache Size")} value={format_number(@stats.cache.size)} />
      </.stat_section>

      <%!-- AI Usage Stats --%>
      <.stat_section
        title={gettext("AI Usage")}
        icon="hero-cpu-chip"
        color="info"
      >
        <.stat_card label={gettext("Requests")} value={format_number(@stats.ai_usage.total_requests)} />
        <.stat_card label={gettext("Tokens")} value={format_number(@stats.ai_usage.total_tokens)} />
        <.stat_card
          label={gettext("Est. Cost")}
          value={"$#{format_float(@stats.ai_usage.estimated_cost)}"}
        />
      </.stat_section>

      <%!-- dllb Backend Stats --%>
      <.stat_section
        title={gettext("dllb Backend")}
        icon="hero-circle-stack"
        color="warning"
      >
        <.stat_card
          label={gettext("Status")}
          value={if @stats.dllb.connected, do: gettext("Connected"), else: gettext("Disconnected")}
          badge_color={if @stats.dllb.connected, do: "badge-success", else: "badge-error"}
        />
        <.stat_card label={gettext("AST Nodes")} value={format_number(@stats.dllb.nodes)} />
        <.stat_card label={gettext("Edges")} value={format_number(@stats.dllb.edges)} />
        <.stat_card label={gettext("Latency")} value={"#{@stats.dllb.latency_ms} ms"} />
      </.stat_section>
    </div>
    """
  end

  # -- Components --

  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :color, :string, required: true
  slot :inner_block, required: true

  defp stat_section(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-sm">
      <div class="card-body p-4">
        <h2 class="card-title text-sm font-semibold flex items-center gap-2">
          <.icon name={@icon} class={"size-5 text-#{@color}"} />
          {@title}
        </h2>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-3 mt-2">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :badge_color, :string, default: nil

  defp stat_card(assigns) do
    ~H"""
    <div class="stat bg-base-100 rounded-box p-3 shadow-xs">
      <div class="stat-title text-xs">{@label}</div>
      <div class="stat-value text-lg">
        <span :if={@badge_color} class={"badge #{@badge_color} badge-sm"}>{@value}</span>
        <span :if={!@badge_color}>{@value}</span>
      </div>
    </div>
    """
  end

  # -- Formatting helpers --

  defp format_number(n) when is_integer(n) and n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  defp format_number(n) when is_integer(n) and n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  defp format_number(n) when is_integer(n), do: Integer.to_string(n)
  defp format_number(n) when is_float(n), do: format_float(n)
  defp format_number(n), do: to_string(n)

  defp format_float(f) when is_float(f), do: :erlang.float_to_binary(f, decimals: 3)
  defp format_float(f), do: to_string(f)

  defp format_percent(f) when is_float(f) do
    "#{:erlang.float_to_binary(f * 100, decimals: 1)}%"
  end

  defp format_percent(_), do: "0.0%"
end
