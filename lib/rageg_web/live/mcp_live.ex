defmodule RagegWeb.McpLive do
  @moduledoc """
  LiveView page for manually executing MCP tools exported by Ragex.

  Features:
  - Interactive searchable list of all MCP tools
  - Auto-generated parameter form based on JSON Schema properties
  - JSON payload editor mode with live syntax validation
  - Automatic prefilling of project path parameter
  - Formatted execution output viewer with timing & status
  """

  use RagegWeb, :live_view

  alias Rageg.MCP

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    tools = MCP.list_tools()

    active_path =
      case Rageg.Profiles.active() do
        %{path: p} -> p
        _ -> ""
      end

    selected_tool = List.first(tools)
    initial_args = default_arguments(selected_tool, active_path)
    json_input = Jason.encode!(initial_args, pretty: true)

    {:ok,
     socket
     |> assign(page_title: gettext("MCP Tools Runner"))
     |> assign(current_path: "/mcp")
     |> assign(project_path: active_path)
     |> assign(tools: tools)
     |> assign(search_query: "")
     |> assign(selected_tool: selected_tool)
     |> assign(mode: :form)
     |> assign(form_args: initial_args)
     |> assign(json_input: json_input)
     |> assign(json_error: nil)
     |> assign(running: false)
     |> assign(result: nil)
     |> assign(error: nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("search_tools", %{"query" => q}, socket) do
    {:noreply, assign(socket, search_query: q)}
  end

  def handle_event("select_tool", %{"name" => name}, socket) do
    if tool = Enum.find(socket.assigns.tools, &(&1.name == name)) do
      initial_args = default_arguments(tool, socket.assigns.project_path)
      json_input = Jason.encode!(initial_args, pretty: true)

      {:noreply,
       socket
       |> assign(
         selected_tool: tool,
         form_args: initial_args,
         json_input: json_input,
         json_error: nil,
         result: nil,
         error: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("switch_mode", %{"mode" => mode_str}, socket) do
    mode = if mode_str == "json", do: :json, else: :form

    # Sync arguments between form and json
    if mode == :json do
      json_input = Jason.encode!(socket.assigns.form_args, pretty: true)
      {:noreply, assign(socket, mode: mode, json_input: json_input, json_error: nil)}
    else
      case Jason.decode(socket.assigns.json_input) do
        {:ok, map} when is_map(map) ->
          {:noreply, assign(socket, mode: mode, form_args: map, json_error: nil)}

        _ ->
          {:noreply, assign(socket, mode: mode)}
      end
    end
  end

  def handle_event("update_form_arg", %{"field" => field, "value" => val}, socket) do
    args = Map.put(socket.assigns.form_args, field, parse_value(val))
    json_input = Jason.encode!(args, pretty: true)
    {:noreply, assign(socket, form_args: args, json_input: json_input)}
  end

  def handle_event("update_json", %{"json" => raw}, socket) do
    case Jason.decode(raw) do
      {:ok, map} when is_map(map) ->
        {:noreply, assign(socket, json_input: raw, form_args: map, json_error: nil)}

      {:error, syntax_err} ->
        {:noreply, assign(socket, json_input: raw, json_error: Exception.message(syntax_err))}
    end
  end

  def handle_event("execute_tool", _params, socket) do
    tool = socket.assigns.selected_tool

    if is_nil(tool) do
      {:noreply, assign(socket, error: gettext("No tool selected"))}
    else
      args =
        if socket.assigns.mode == :json do
          case Jason.decode(socket.assigns.json_input) do
            {:ok, map} when is_map(map) -> map
            _ -> nil
          end
        else
          socket.assigns.form_args
        end

      if is_nil(args) do
        {:noreply, assign(socket, error: gettext("Invalid JSON parameters"))}
      else
        pid = self()
        tool_name = tool.name

        {:ok, task_pid} =
          Task.start(fn ->
            res = MCP.call_tool(tool_name, args)
            send(pid, {:tool_executed, res})
          end)

        Process.monitor(task_pid)

        {:noreply, assign(socket, running: true, error: nil, result: nil)}
      end
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:rageg_profile_changed, profile}, socket) do
    path = (profile && profile.path) || ""

    # Update path pre-fills if active
    form_args =
      if socket.assigns.selected_tool do
        update_path_arg(socket.assigns.form_args, path)
      else
        socket.assigns.form_args
      end

    json_input = Jason.encode!(form_args, pretty: true)

    {:noreply,
     socket
     |> assign(project_path: path, form_args: form_args, json_input: json_input)}
  end

  def handle_info({:tool_executed, {:ok, res}}, socket) do
    {:noreply, assign(socket, running: false, result: res, error: nil)}
  end

  def handle_info({:tool_executed, {:error, reason}}, socket) do
    {:noreply, assign(socket, running: false, error: to_string(reason))}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, assign(socket, running: false)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold flex items-center gap-2">
            <.icon name="hero-command-line" class="size-7 text-primary" />
            {gettext("MCP Tools Runner")}
          </h1>
          <p class="text-sm text-base-content/60 mt-1">
            {gettext("Interactively execute exported Ragex Model Context Protocol (MCP) tools.")}
          </p>
        </div>
        <div class="flex items-center gap-2">
          <span class="badge badge-primary badge-outline text-xs font-mono font-semibold">
            {length(@tools)} {gettext("tools registered")}
          </span>
        </div>
      </div>

      <%!-- Main Grid Layout --%>
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        <%!-- Left Sidebar: Tool Selector --%>
        <div class="lg:col-span-4 space-y-3">
          <div class="card bg-base-200 border border-base-300 shadow-sm">
            <div class="card-body p-3 space-y-3">
              <div class="form-control w-full">
                <input
                  type="text"
                  id="mcp-search-input"
                  value={@search_query}
                  placeholder={gettext("Search tools by name or description...")}
                  class="input input-sm input-bordered font-mono"
                  phx-keyup="search_tools"
                  phx-value-query=""
                />
              </div>

              <% filtered = MCP.filter_tools(@tools, @search_query) %>
              <div class="divide-y divide-base-300 max-h-[600px] overflow-y-auto pr-1" id="mcp-tools-list">
                <button
                  :for={tool <- filtered}
                  id={"mcp-tool-item-#{tool.name}"}
                  class={[
                    "w-full text-left p-2.5 rounded-lg transition-colors flex flex-col gap-1 my-0.5",
                    if(@selected_tool && @selected_tool.name == tool.name,
                      do: "bg-primary text-primary-content font-medium shadow-xs",
                      else: "hover:bg-base-300/60"
                    )
                  ]}
                  phx-click="select_tool"
                  phx-value-name={tool.name}
                >
                  <div class="flex items-center justify-between gap-2">
                    <span class="font-mono text-xs font-bold truncate">{tool.name}</span>
                    <span class={[
                      "badge badge-xs font-mono shrink-0",
                      if(@selected_tool && @selected_tool.name == tool.name, do: "badge-neutral", else: "badge-ghost")
                    ]}>
                      {param_count(tool)} {gettext("args")}
                    </span>
                  </div>
                  <p class={[
                    "text-[11px] line-clamp-2 leading-tight",
                    if(@selected_tool && @selected_tool.name == tool.name, do: "opacity-90", else: "text-base-content/60")
                  ]}>
                    {tool.description}
                  </p>
                </button>
              </div>
            </div>
          </div>
        </div>

        <%!-- Right Main Panel: Executor & Results --%>
        <div class="lg:col-span-8 space-y-6">
          <div :if={@selected_tool} class="card bg-base-200 border border-base-300 shadow-sm" id="mcp-executor-card">
            <div class="card-body p-5 space-y-4">
              <%!-- Selected Tool Header --%>
              <div class="flex items-start justify-between gap-4 pb-3 border-b border-base-300">
                <div>
                  <div class="flex items-center gap-2">
                    <h2 class="text-xl font-bold font-mono text-primary">{@selected_tool.name}</h2>
                    <span class="badge badge-sm badge-secondary font-mono">MCP Tool</span>
                  </div>
                  <p class="text-xs text-base-content/70 mt-1">
                    {@selected_tool.description}
                  </p>
                </div>

                <%!-- Mode switcher --%>
                <div class="join border border-base-300 rounded-lg shrink-0">
                  <button
                    class={["join-item btn btn-xs", if(@mode == :form, do: "btn-primary", else: "btn-ghost")]}
                    phx-click="switch_mode"
                    phx-value-mode="form"
                  >
                    {gettext("Form")}
                  </button>
                  <button
                    class={["join-item btn btn-xs", if(@mode == :json, do: "btn-primary", else: "btn-ghost")]}
                    phx-click="switch_mode"
                    phx-value-mode="json"
                  >
                    {gettext("JSON")}
                  </button>
                </div>
              </div>

              <%!-- Parameter Form / JSON Editor --%>
              <div class="space-y-4">
                <%= if @mode == :form do %>
                  <% props = get_schema_properties(@selected_tool) %>
                  <div :if={props == %{}} class="text-xs text-base-content/50 italic py-2">
                    {gettext("This tool takes no parameters.")}
                  </div>

                  <div :if={props != %{}} class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div :for={{prop_name, prop_spec} <- props} class="form-control w-full">
                      <label class="label py-1">
                        <span class="label-text text-xs font-mono font-semibold">
                          {prop_name}
                          <span :if={is_required?(@selected_tool, prop_name)} class="text-error ml-0.5">*</span>
                        </span>
                        <span class="label-text-alt text-[10px] text-base-content/50 font-mono">
                          {Map.get(prop_spec, "type", "string")}
                        </span>
                      </label>

                      <%= cond do %>
                        <% Map.has_key?(prop_spec, "enum") -> %>
                          <select
                            id={"form-input-#{prop_name}"}
                            class="select select-sm select-bordered w-full font-mono text-xs"
                            phx-change="update_form_arg"
                            phx-value-field={prop_name}
                            phx-value-value=""
                          >
                            <option
                              :for={opt <- Map.get(prop_spec, "enum", [])}
                              value={to_string(opt)}
                              selected={to_string(Map.get(@form_args, prop_name)) == to_string(opt)}
                            >
                              {opt}
                            </option>
                          </select>

                        <% Map.get(prop_spec, "type") == "boolean" -> %>
                          <label class="cursor-pointer label justify-start gap-3 bg-base-100 px-3 py-1.5 rounded-lg border border-base-300">
                            <input
                              type="checkbox"
                              id={"form-input-#{prop_name}"}
                              class="checkbox checkbox-sm checkbox-primary"
                              checked={Map.get(@form_args, prop_name) == true}
                              phx-click="update_form_arg"
                              phx-value-field={prop_name}
                              phx-value-value={to_string(!Map.get(@form_args, prop_name, false))}
                            />
                            <span class="label-text text-xs font-mono">{prop_name}</span>
                          </label>

                        <% true -> %>
                          <input
                            type="text"
                            id={"form-input-#{prop_name}"}
                            value={to_string(Map.get(@form_args, prop_name, ""))}
                            placeholder={Map.get(prop_spec, "description", "")}
                            class="input input-sm input-bordered font-mono text-xs w-full"
                            phx-keyup="update_form_arg"
                            phx-value-field={prop_name}
                            phx-value-value=""
                          />
                      <% end %>
                      <span :if={Map.has_key?(prop_spec, "description")} class="text-[10px] text-base-content/50 mt-0.5">
                        {Map.get(prop_spec, "description")}
                      </span>
                    </div>
                  </div>
                <% else %>
                  <div class="form-control w-full">
                    <label class="label py-1">
                      <span class="label-text text-xs font-mono font-semibold">{gettext("JSON Arguments Payload")}</span>
                    </label>
                    <textarea
                      id="mcp-json-textarea"
                      rows="7"
                      class="textarea textarea-bordered font-mono text-xs w-full"
                      phx-keyup="update_json"
                      phx-value-json=""
                    >{@json_input}</textarea>
                    <div :if={@json_error} class="text-xs text-error mt-1 flex items-center gap-1 font-mono">
                      <.icon name="hero-exclamation-circle" class="size-4 shrink-0" />
                      <span>{@json_error}</span>
                    </div>
                  </div>
                <% end %>
              </div>

              <%!-- Action Toolbar --%>
              <div class="flex items-center justify-between pt-2">
                <div class="text-xs text-base-content/50 font-mono">
                  {gettext("Target Profile")}: <span class="font-bold">{if @project_path == "", do: gettext("None"), else: Path.basename(@project_path)}</span>
                </div>

                <button
                  id="mcp-execute-btn"
                  class="btn btn-primary gap-2"
                  phx-click="execute_tool"
                  disabled={@running or (@mode == :json and @json_error != nil)}
                >
                  <span :if={@running} class="loading loading-spinner loading-sm"></span>
                  <.icon :if={!@running} name="hero-play" class="size-5" />
                  {if @running, do: gettext("Executing..."), else: gettext("Execute Tool")}
                </button>
              </div>
            </div>
          </div>

          <%!-- Global Error Alert --%>
          <div :if={@error} class="alert alert-error shadow-sm" id="mcp-error">
            <.icon name="hero-exclamation-triangle" class="size-5" />
            <span>{@error}</span>
          </div>

          <%!-- Result Box --%>
          <div :if={@result} class="card bg-base-200 border border-base-300 shadow-sm" id="mcp-result-card">
            <div class="card-body p-4 space-y-3">
              <div class="flex items-center justify-between pb-2 border-b border-base-300">
                <div class="flex items-center gap-2">
                  <.icon name="hero-code-bracket" class="size-5 text-primary" />
                  <h3 class="font-bold text-sm">{gettext("Tool Result")}</h3>
                  <span class={[
                    "badge badge-sm font-mono font-semibold",
                    if(@result.is_error, do: "badge-error", else: "badge-success")
                  ]}>
                    {if @result.is_error, do: gettext("Error"), else: gettext("Success")}
                  </span>
                </div>

                <div class="flex items-center gap-2">
                  <span class="badge badge-ghost badge-sm font-mono">
                    {@result.timing_ms} ms
                  </span>
                </div>
              </div>

              <%!-- Code Output Display --%>
              <div class="bg-base-300 rounded-xl p-3 border border-base-300 font-mono text-xs overflow-x-auto max-h-[500px]">
                <pre class="whitespace-pre-wrap break-all text-base-content/90 font-mono">{format_output(@result.output)}</pre>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helpers

  defp default_arguments(nil, _path), do: %{}

  defp default_arguments(tool, path) do
    props = get_schema_properties(tool)

    Enum.into(props, %{}, fn {name, spec} ->
      val =
        cond do
          name in ["path", "project_path", "directory", "dir"] and path != "" ->
            path

          Map.has_key?(spec, "default") ->
            Map.get(spec, "default")

          Map.has_key?(spec, "enum") ->
            List.first(Map.get(spec, "enum"))

          Map.get(spec, "type") == "boolean" ->
            false

          Map.get(spec, "type") == "integer" or Map.get(spec, "type") == "number" ->
            0

          true ->
            ""
        end

      {name, val}
    end)
  end

  defp get_schema_properties(%{inputSchema: %{properties: props}}) when is_map(props), do: props

  defp get_schema_properties(%{"inputSchema" => %{"properties" => props}}) when is_map(props),
    do: props

  defp get_schema_properties(_), do: %{}

  defp param_count(tool) do
    props = get_schema_properties(tool)
    map_size(props)
  end

  defp is_required?(%{inputSchema: %{required: reqs}}, prop_name) when is_list(reqs) do
    prop_name in reqs
  end

  defp is_required?(%{"inputSchema" => %{"required" => reqs}}, prop_name) when is_list(reqs) do
    prop_name in reqs
  end

  defp is_required?(_, _), do: false

  defp parse_value("true"), do: true
  defp parse_value("false"), do: false

  defp parse_value(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} -> int
      _ -> val
    end
  end

  defp parse_value(val), do: val

  defp update_path_arg(args, path) when is_map(args) do
    Enum.reduce(["path", "project_path", "directory", "dir"], args, fn key, acc ->
      if Map.has_key?(acc, key) do
        Map.put(acc, key, path)
      else
        acc
      end
    end)
  end

  defp format_output(str) when is_binary(str) do
    case Jason.decode(str) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      _ -> str
    end
  end

  defp format_output(map) when is_map(map) or is_list(map) do
    Jason.encode!(map, pretty: true)
  end

  defp format_output(other), do: inspect(other, pretty: true)
end
