defmodule Rageg.Plugins do
  @moduledoc """
  Context module for managing Ragex domain plugins, topological dependency resolution,
  dynamic tool schemas, and safety-classified parallel execution.

  Wraps `Ragex.Plugin.Registry` and `Ragex.Plugin.EventBus`.
  """

  @doc """
  Lists all registered plugins in topological dependency and priority order.
  """
  def list_plugins do
    if Process.whereis(Ragex.Plugin.Registry) do
      Ragex.Plugin.Registry.list_plugins()
    else
      []
    end
  rescue
    _ -> []
  end

  @doc """
  Enables a registered plugin by ID.
  """
  def enable_plugin(plugin_id) do
    with {:ok, id} <- normalize_id(plugin_id) do
      if Process.whereis(Ragex.Plugin.Registry) do
        Ragex.Plugin.Registry.enable_plugin(id)
      else
        {:error, :registry_not_running}
      end
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Disables a registered plugin by ID.
  """
  def disable_plugin(plugin_id) do
    with {:ok, id} <- normalize_id(plugin_id) do
      if Process.whereis(Ragex.Plugin.Registry) do
        Ragex.Plugin.Registry.disable_plugin(id)
      else
        {:error, :registry_not_running}
      end
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Lists tool schemas provided by active plugins.
  """
  def list_plugin_tools do
    if Process.whereis(Ragex.Plugin.Registry) do
      Ragex.Plugin.Registry.list_tools()
    else
      []
    end
  rescue
    _ -> []
  end

  @doc """
  Lists tools currently running in parallel via Task.Supervisor.
  """
  def list_running_tools do
    if Process.whereis(Ragex.Plugin.Registry) do
      Ragex.Plugin.Registry.list_running_tools()
    else
      []
    end
  rescue
    _ -> []
  end

  @doc """
  Dispatches multiple tool calls concurrently (for non-destructive tools).
  """
  def dispatch_tools(tool_requests, opts \\ []) do
    if Process.whereis(Ragex.Plugin.Registry) do
      Ragex.Plugin.Registry.dispatch_tools(tool_requests, opts)
    else
      {:error, :registry_not_running}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Dispatches a single tool call via the plugin orchestrator.
  """
  def dispatch_tool(tool_name, args) when is_binary(tool_name) and is_map(args) do
    if Process.whereis(Ragex.Plugin.Registry) do
      Ragex.Plugin.Registry.dispatch_tool(tool_name, args)
    else
      {:error, :registry_not_running}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Returns topological dependency mapping for all registered plugins.
  """
  def list_plugin_dependencies do
    if Process.whereis(Ragex.Plugin.Registry) do
      Ragex.Plugin.Registry.list_plugin_dependencies()
    else
      %{}
    end
  rescue
    _ -> %{}
  end

  defp normalize_id(id) when is_atom(id), do: {:ok, id}
  defp normalize_id(id) when is_binary(id), do: Rageg.Atom.existing(id)
end
