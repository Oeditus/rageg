defmodule RagegWeb.QualityLive do
  @moduledoc """
  Code Quality page -- tabbed interface for all quality analysis dimensions.

  Tabs: Code Smells, Security, Dead Code, Duplication, Complexity, Business Logic.
  Each tab lazily loads data from `Rageg.Quality` on first activation.
  """

  use RagegWeb, :live_view

  alias Rageg.Quality

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Code Quality"))
     |> assign(current_path: "/quality")
     |> assign(active_tab: :smells)
     |> assign(loading: false)
     |> assign(items: [])
     |> assign(summary: nil)
     |> assign(analysis_path: nil)}
  end

  @impl Phoenix.LiveView
  def handle_params(_params, _uri, socket) do
    if connected?(socket) do
      path = detect_project_path()
      send(self(), {:load_tab, socket.assigns.active_tab, path})
      {:noreply, assign(socket, loading: true, analysis_path: path)}
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)
    send(self(), {:load_tab, tab, socket.assigns.analysis_path})
    {:noreply, assign(socket, active_tab: tab, loading: true, items: [])}
  end

  @impl Phoenix.LiveView
  def handle_info({:load_tab, tab, path}, socket) do
    items = fetch_tab_data(tab, path)
    summary = Quality.summary(path || "lib")

    {:noreply,
     socket
     |> assign(items: items, loading: false, summary: summary, active_tab: tab)}
  end

  # -- Render --

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Header with summary badges --%>
      <div class="flex items-center justify-between flex-wrap gap-2">
        <div>
          <h1 class="text-2xl font-bold">{gettext("Code Quality")}</h1>
          <p class="text-sm text-base-content/60">
            {gettext("Analysis results across all quality dimensions")}
          </p>
        </div>
        <div :if={@summary} class="flex gap-2 flex-wrap">
          <.summary_badge
            :for={{tab, label, _icon} <- Quality.tabs()}
            label={label}
            count={Map.get(@summary, tab, 0)}
            active={@active_tab == tab}
          />
        </div>
      </div>

      <%!-- Tab bar --%>
      <div role="tablist" class="tabs tabs-bordered">
        <button
          :for={{tab, label, icon} <- Quality.tabs()}
          role="tab"
          class={["tab gap-2", if(@active_tab == tab, do: "tab-active", else: "")]}
          phx-click="switch_tab"
          phx-value-tab={tab}
        >
          <.icon name={icon} class="size-4" />
          {label}
        </button>
      </div>

      <%!-- Content --%>
      <div :if={@loading} class="flex justify-center py-12">
        <span class="loading loading-spinner loading-lg text-primary"></span>
      </div>

      <div :if={!@loading}>
        <.tab_content tab={@active_tab} items={@items} />
      </div>
    </div>
    """
  end

  # -- Tab content components --

  defp tab_content(%{tab: :smells} = assigns) do
    ~H"""
    <.findings_table
      items={@items}
      columns={[
        {"Type", fn i -> format_atom(i[:type]) end},
        {"Severity", fn i -> i[:severity] end},
        {"File", fn i -> short_path(i[:file]) end},
        {"Description", fn i -> i[:description] end}
      ]}
      empty_msg={gettext("No code smells detected")}
    />
    """
  end

  defp tab_content(%{tab: :security} = assigns) do
    ~H"""
    <.findings_table
      items={@items}
      columns={[
        {"Category", fn i -> format_atom(i[:category]) end},
        {"Severity", fn i -> i[:severity] end},
        {"File", fn i -> short_path(i[:file]) end},
        {"Description", fn i -> i[:description] end}
      ]}
      empty_msg={gettext("No security vulnerabilities found")}
    />
    """
  end

  defp tab_content(%{tab: :dead_code} = assigns) do
    ~H"""
    <.findings_table
      items={@items}
      columns={[
        {"Function", fn i -> format_function(i[:function]) end},
        {"Confidence", fn i -> format_confidence(i[:confidence]) end},
        {"Visibility", fn i -> i[:visibility] end},
        {"Reason", fn i -> i[:reason] end}
      ]}
      empty_msg={gettext("No dead code detected")}
    />
    """
  end

  defp tab_content(%{tab: :duplication} = assigns) do
    ~H"""
    <.findings_table
      items={@items}
      columns={[
        {"Type", fn i -> format_atom(i[:clone_type] || i[:type]) end},
        {"File 1", fn i -> short_path(i[:file1]) end},
        {"File 2", fn i -> short_path(i[:file2]) end},
        {"Similarity", fn i -> format_percent(i[:similarity]) end}
      ]}
      empty_msg={gettext("No code duplication detected")}
    />
    """
  end

  defp tab_content(%{tab: :complexity} = assigns) do
    ~H"""
    <.findings_table
      items={@items}
      columns={[
        {"Function", fn i -> format_complex_fn(i) end},
        {"Cyclomatic", fn i -> i[:cyclomatic] || i[:complexity] end},
        {"Cognitive", fn i -> i[:cognitive] end},
        {"File", fn i -> short_path(i[:file] || i[:path]) end}
      ]}
      empty_msg={gettext("No complex functions found")}
    />
    """
  end

  defp tab_content(%{tab: :business_logic} = assigns) do
    ~H"""
    <.findings_table
      items={@items}
      columns={[
        {"Analyzer", fn i -> format_atom(i[:analyzer]) end},
        {"Severity", fn i -> i[:severity] end},
        {"File", fn i -> short_path(i[:file]) end},
        {"Description", fn i -> i[:description] || i[:message] end}
      ]}
      empty_msg={gettext("No business logic issues found")}
    />
    """
  end

  defp tab_content(assigns) do
    ~H"""
    <div class="text-center py-8 text-base-content/50">
      {gettext("No data available")}
    </div>
    """
  end

  # -- Reusable findings table --

  attr :items, :list, required: true
  attr :columns, :list, required: true
  attr :empty_msg, :string, required: true

  defp findings_table(assigns) do
    ~H"""
    <div :if={@items == []} class="text-center py-12 text-base-content/50">
      <.icon name="hero-check-circle" class="size-12 mx-auto mb-2 text-success/40" />
      <p>{@empty_msg}</p>
    </div>
    <div :if={@items != []} class="overflow-x-auto">
      <table class="table table-sm table-zebra">
        <thead>
          <tr>
            <th :for={{header, _fn} <- @columns}>{header}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={item <- @items}>
            <td :for={{_header, accessor} <- @columns}>
              <.cell_value value={accessor.(item)} />
            </td>
          </tr>
        </tbody>
      </table>
      <div class="text-xs text-base-content/50 mt-2 text-right">
        {length(@items)} {gettext("items")}
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :active, :boolean, default: false

  defp summary_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      if(@active, do: "badge-primary", else: "badge-ghost"),
      if(@count > 0 and not @active, do: "badge-warning", else: "")
    ]}>
      {@label}: {@count}
    </span>
    """
  end

  attr :value, :any, required: true

  defp cell_value(%{value: value} = assigns)
       when is_atom(value) and value in [:critical, :high, :medium, :low] do
    ~H"""
    <span class={[
      "badge badge-sm",
      severity_class(@value)
    ]}>
      {@value}
    </span>
    """
  end

  defp cell_value(assigns) do
    ~H"""
    <span class="truncate max-w-xs inline-block">{@value}</span>
    """
  end

  # -- Helpers --

  defp fetch_tab_data(:smells, path) do
    {:ok, items} = Quality.fetch_smells(path || "lib")
    items
  end

  defp fetch_tab_data(:security, path) do
    {:ok, items} = Quality.fetch_security(path || "lib")
    items
  end

  defp fetch_tab_data(:dead_code, _path) do
    {:ok, items} = Quality.fetch_dead_code()
    items
  end

  defp fetch_tab_data(:duplication, path) do
    {:ok, items} = Quality.fetch_duplication(path || "lib")
    items
  end

  defp fetch_tab_data(:complexity, path) do
    {:ok, items} = Quality.fetch_complexity(path || "lib")
    items
  end

  defp fetch_tab_data(:business_logic, path) do
    {:ok, items} = Quality.fetch_business_logic(path || "lib")
    items
  end

  defp fetch_tab_data(_, _), do: []

  defp detect_project_path do
    # Use the auto-analyze dirs config if available, otherwise default
    case Application.get_env(:ragex, :auto_analyze_dirs) do
      [path | _] -> path
      _ -> nil
    end
  end

  defp severity_class(:critical), do: "badge-error"
  defp severity_class(:high), do: "badge-warning"
  defp severity_class(:medium), do: "badge-info"
  defp severity_class(_), do: "badge-ghost"

  defp format_atom(nil), do: "-"
  defp format_atom(a) when is_atom(a), do: a |> to_string() |> String.replace("_", " ")
  defp format_atom(s), do: to_string(s)

  defp format_function({:function, mod, name, arity}), do: "#{mod}.#{name}/#{arity}"
  defp format_function(%{module: m, name: n, arity: a}), do: "#{m}.#{n}/#{a}"
  defp format_function(other), do: inspect(other)

  defp format_confidence(nil), do: "-"
  defp format_confidence(c) when is_float(c), do: "#{round(c * 100)}%"
  defp format_confidence(c), do: to_string(c)

  defp format_percent(nil), do: "-"
  defp format_percent(s) when is_float(s), do: "#{round(s * 100)}%"
  defp format_percent(s), do: to_string(s)

  defp format_complex_fn(%{function: f, arity: a, module: m}), do: "#{m}.#{f}/#{a}"
  defp format_complex_fn(%{name: n}), do: to_string(n)
  defp format_complex_fn(i), do: inspect(i)

  defp short_path(nil), do: "-"

  defp short_path(path) when is_binary(path) do
    path |> String.split("/") |> Enum.take(-3) |> Enum.join("/")
  end

  defp short_path(p), do: to_string(p)
end
