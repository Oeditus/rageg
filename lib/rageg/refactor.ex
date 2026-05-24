defmodule Rageg.Refactor do
  @moduledoc """
  Context module for visual refactoring operations.

  Wraps `Ragex.Editor.Refactor`, `Ragex.Editor.Preview`, and
  `Ragex.Editor.Undo` to provide the RefactorLive page with
  operation execution, preview, and rollback capabilities.
  """

  alias Ragex.Editor.{Refactor, Undo}

  @type operation ::
          :rename_function
          | :rename_module
          | :extract_function
          | :inline_function
          | :convert_visibility
          | :rename_parameter
          | :modify_attributes
          | :change_signature

  @doc "Available refactoring operations with display names, icons, and descriptions."
  @spec operations() :: [{operation(), String.t(), String.t(), String.t()}]
  def operations do
    [
      {:rename_function, "Rename Function", "hero-pencil-square",
       "Rename a function and update all call sites across the project"},
      {:rename_module, "Rename Module", "hero-pencil",
       "Rename a module and update all references"},
      {:extract_function, "Extract Function", "hero-scissors",
       "Extract a code range into a new function"},
      {:inline_function, "Inline Function", "hero-arrow-down-on-square",
       "Replace function calls with the function body"},
      {:convert_visibility, "Convert Visibility", "hero-eye", "Toggle between def and defp"},
      {:change_signature, "Change Signature", "hero-adjustments-horizontal",
       "Add, remove, reorder, or rename parameters"}
    ]
  end

  @doc "Returns the parameter fields needed for a given operation."
  @spec operation_fields(operation()) :: [{atom(), String.t(), String.t()}]
  def operation_fields(:rename_function) do
    [
      {:module, "Module", "text"},
      {:old_name, "Current Name", "text"},
      {:new_name, "New Name", "text"},
      {:arity, "Arity", "number"}
    ]
  end

  def operation_fields(:rename_module) do
    [
      {:old_name, "Current Module", "text"},
      {:new_name, "New Module", "text"}
    ]
  end

  def operation_fields(:extract_function) do
    [
      {:module, "Module", "text"},
      {:source_function, "Source Function", "text"},
      {:source_arity, "Source Arity", "number"},
      {:new_name, "New Function Name", "text"},
      {:line_start, "Start Line", "number"},
      {:line_end, "End Line", "number"}
    ]
  end

  def operation_fields(:inline_function) do
    [
      {:module, "Module", "text"},
      {:function_name, "Function Name", "text"},
      {:arity, "Arity", "number"}
    ]
  end

  def operation_fields(:convert_visibility) do
    [
      {:module, "Module", "text"},
      {:function_name, "Function Name", "text"},
      {:arity, "Arity", "number"}
    ]
  end

  def operation_fields(:change_signature) do
    [
      {:module, "Module", "text"},
      {:function_name, "Function Name", "text"},
      {:arity, "Arity", "number"},
      {:new_params, "New Parameters (comma-separated)", "text"}
    ]
  end

  def operation_fields(_), do: []

  @doc """
  Executes a refactoring operation.

  Returns `{:ok, result}` or `{:error, reason}`.
  """
  @spec execute(operation(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(:rename_function, params, opts) do
    Refactor.rename_function(
      params.module,
      params.old_name,
      params.new_name,
      params.arity,
      opts
    )
  rescue
    e -> {:error, Exception.message(e)}
  end

  def execute(:rename_module, params, opts) do
    Refactor.rename_module(params.old_name, params.new_name, opts)
  rescue
    e -> {:error, Exception.message(e)}
  end

  def execute(:extract_function, params, opts) do
    Refactor.extract_function(
      params.module,
      params.source_function,
      params.source_arity,
      params.new_name,
      {params.line_start, params.line_end},
      opts
    )
  rescue
    e -> {:error, Exception.message(e)}
  end

  def execute(_, _params, _opts), do: {:error, "Operation not yet implemented"}

  @doc "Undoes the last refactoring for a project."
  @spec undo(String.t()) :: {:ok, map()} | {:error, term()}
  def undo(project_path) do
    Undo.undo(project_path)
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc "Lists the undo history for a project."
  @spec undo_history(String.t(), keyword()) :: {:ok, list()} | {:error, term()}
  def undo_history(project_path, opts \\ []) do
    Undo.list_undo_stack(project_path, opts)
  rescue
    _ -> {:ok, []}
  end
end
