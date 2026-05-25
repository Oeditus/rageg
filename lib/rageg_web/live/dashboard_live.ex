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
     |> assign(stats: stats)}
  end

  @impl Phoenix.LiveView
  def handle_info({:stats_updated, stats}, socket) do
    {:noreply, assign(socket, stats: stats)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">{gettext("Dashboard")}</h1>
          <p class="text-sm text-base-content/60">
            {gettext("Real-time statistics from Ragex and dllb")}
          </p>
        </div>
        <div class="badge badge-outline badge-sm">
          {gettext("Updated")} {Calendar.strftime(@stats.fetched_at, "%H:%M:%S")}
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
