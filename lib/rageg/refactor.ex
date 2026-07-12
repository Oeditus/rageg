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
       "Add, remove, reorder, or rename parameters"},
      {:rename_parameter, "Rename Parameter", "hero-tag",
       "Rename a parameter within a function body"},
      {:move_function, "Move Function", "hero-arrows-right-left",
       "Move a function from one module to another"},
      {:extract_module, "Extract Module", "hero-squares-plus",
       "Extract multiple functions into a new module"}
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
      {:arity, "Arity", "number"},
      {:visibility, "Visibility (public/private)", "text"}
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

  def operation_fields(:rename_parameter) do
    [
      {:module, "Module", "text"},
      {:function, "Function Name", "text"},
      {:arity, "Arity", "number"},
      {:old_param, "Current Parameter Name", "text"},
      {:new_param, "New Parameter Name", "text"}
    ]
  end

  def operation_fields(:move_function) do
    [
      {:source_module, "Source Module", "text"},
      {:target_module, "Target Module", "text"},
      {:function_name, "Function Name", "text"},
      {:arity, "Arity", "number"}
    ]
  end

  def operation_fields(:extract_module) do
    [
      {:source_module, "Source Module", "text"},
      {:new_module, "New Module Name", "text"},
      {:functions, "Functions (comma-separated name/arity, e.g. f1/1, f2/2)", "text"}
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
      normalize_module(params.module),
      to_atom(params.old_name),
      to_atom(params.new_name),
      params.arity,
      opts
    )
  rescue
    e -> {:error, Exception.message(e)}
  end

  def execute(:rename_module, params, opts) do
    Refactor.rename_module(
      normalize_module(params.old_name),
      normalize_module(params.new_name),
      opts
    )
  rescue
    e -> {:error, Exception.message(e)}
  end

  def execute(:extract_function, params, opts) do
    Refactor.extract_function(
      normalize_module(params.module),
      to_atom(params.source_function),
      params.source_arity,
      to_atom(params.new_name),
      {params.line_start, params.line_end},
      opts
    )
  rescue
    e -> {:error, Exception.message(e)}
  end

  def execute(:inline_function, params, opts) do
    Refactor.inline_function(
      normalize_module(params.module),
      to_atom(params.function_name),
      params.arity,
      opts
    )
  rescue
    e -> {:error, Exception.message(e)}
  end

  def execute(:convert_visibility, params, opts) do
    visibility =
      case to_string(params.visibility) |> String.trim() |> String.downcase() do
        "public" -> :public
        "private" -> :private
        other -> String.to_existing_atom(other)
      end

    Refactor.convert_visibility(
      normalize_module(params.module),
      to_atom(params.function_name),
      params.arity,
      visibility,
      opts
    )
  rescue
    e -> {:error, Exception.message(e)}
  end

  def execute(:rename_parameter, params, opts) do
    Refactor.rename_parameter(
      normalize_module(params.module),
      to_atom(params.function),
      params.arity,
      to_atom(params.old_param),
      to_atom(params.new_param),
      opts
    )
  rescue
    e -> {:error, Exception.message(e)}
  end

  def execute(:change_signature, params, opts) do
    signature_changes = parse_new_params(params.new_params, params.arity)

    Refactor.change_signature(
      normalize_module(params.module),
      to_atom(params.function_name),
      params.arity,
      signature_changes,
      opts
    )
  rescue
    e -> {:error, Exception.message(e)}
  end

  def execute(:move_function, params, opts) do
    Refactor.move_function(
      normalize_module(params.source_module),
      normalize_module(params.target_module),
      to_atom(params.function_name),
      params.arity,
      opts
    )
  rescue
    e -> {:error, Exception.message(e)}
  end

  def execute(:extract_module, params, opts) do
    functions = parse_functions_list(params.functions)

    Refactor.extract_module(
      normalize_module(params.source_module),
      normalize_module(params.new_module),
      functions,
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

  # -- Helpers --

  defp normalize_module(module_str) when is_binary(module_str) do
    module_str = String.trim(module_str)

    if String.starts_with?(module_str, "Elixir.") do
      String.to_atom(module_str)
    else
      String.to_atom("Elixir." <> module_str)
    end
  end

  defp normalize_module(module_atom) when is_atom(module_atom) do
    normalize_module(Atom.to_string(module_atom))
  end

  defp to_atom(val) when is_atom(val), do: val

  defp to_atom(val) when is_binary(val) do
    val |> String.trim() |> String.to_atom()
  end

  defp parse_new_params(new_params_str, old_arity) do
    new_names =
      new_params_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    new_arity = length(new_names)

    cond do
      new_arity == old_arity ->
        Enum.with_index(new_names)
        |> Enum.map(fn {name, idx} -> {:rename, idx, name} end)

      new_arity > old_arity ->
        renames =
          Enum.take(new_names, old_arity)
          |> Enum.with_index()
          |> Enum.map(fn {name, idx} -> {:rename, idx, name} end)

        adds =
          Enum.drop(new_names, old_arity)
          |> Enum.with_index(old_arity)
          |> Enum.map(fn {name, idx} -> {:add, name, idx, nil} end)

        renames ++ adds

      new_arity < old_arity ->
        renames =
          Enum.with_index(new_names)
          |> Enum.map(fn {name, idx} -> {:rename, idx, name} end)

        removes =
          (old_arity - 1)..new_arity
          |> Enum.map(fn idx -> {:remove, idx} end)

        renames ++ removes
    end
  end

  defp parse_functions_list(functions_str) do
    functions_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn entry ->
      case String.split(entry, "/") do
        [name, arity_str] ->
          {String.to_atom(name), String.to_integer(arity_str)}

        [name] ->
          {String.to_atom(name), 0}
      end
    end)
  end
end
