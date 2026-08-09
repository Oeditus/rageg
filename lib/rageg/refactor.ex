defmodule Rageg.Refactor do
  @moduledoc """
  Context module for visual refactoring operations.

  Wraps `Ragex.Editor.Refactor`, `Ragex.Editor.Preview`, and
  `Ragex.Editor.Undo` to provide the RefactorLive page with
  operation execution, preview, and rollback capabilities.
  """

  alias Ragex.Editor.{Refactor, Undo}
  alias Ragex.Graph.Store

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

  @doc """
  Generates a dry-run preview of a refactoring operation, calculating in-memory diffs
  and checking for potential conflicts.
  """
  @spec preview(operation(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def preview(operation, params, _opts \\ []) do
    params = normalize_params_for_preview(operation, params)

    with {:ok, files} <- find_affected_files(operation, params),
         {:ok, file_contents} <- read_files(files, operation, params),
         {:ok, transformed_contents} <- apply_memory_transforms(operation, params, file_contents),
         {:ok, diffs} <- generate_preview_diffs(transformed_contents),
         {:ok, conflicts} <- check_operation_conflicts(operation, params) do
      {:ok, %{diffs: diffs, conflicts: conflicts}}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # -- Preview Helpers --

  defp normalize_params_for_preview(operation, params) do
    # Ensure keys are atoms
    params =
      Map.new(params, fn
        {k, v} when is_binary(k) -> {safe_atom(k), v}
        {k, v} -> {k, v}
      end)

    normalize_params(operation, params)
  end

  defp normalize_params(:rename_function, params) do
    %{
      module: normalize_module(params.module),
      old_name: to_atom(params.old_name),
      new_name: to_atom(params.new_name),
      arity: to_integer(params.arity)
    }
  end

  defp normalize_params(:rename_module, params) do
    %{
      old_name: normalize_module(params.old_name),
      new_name: normalize_module(params.new_name)
    }
  end

  defp normalize_params(:extract_function, params) do
    %{
      module: normalize_module(params.module),
      source_function: to_atom(params.source_function),
      source_arity: to_integer(params.source_arity),
      new_name: to_atom(params.new_name),
      line_start: to_integer(params.line_start),
      line_end: to_integer(params.line_end)
    }
  end

  defp normalize_params(:inline_function, params) do
    %{
      module: normalize_module(params.module),
      function_name: to_atom(params.function_name),
      arity: to_integer(params.arity)
    }
  end

  defp normalize_params(:convert_visibility, params) do
    %{
      module: normalize_module(params.module),
      function_name: to_atom(params.function_name),
      arity: to_integer(params.arity),
      visibility:
        case to_string(params.visibility) |> String.trim() |> String.downcase() do
          "public" -> :public
          "private" -> :private
          other -> String.to_existing_atom(other)
        end
    }
  end

  defp normalize_params(:rename_parameter, params) do
    %{
      module: normalize_module(params.module),
      function: to_atom(params.function),
      arity: to_integer(params.arity),
      old_param: to_atom(params.old_param),
      new_param: to_atom(params.new_param)
    }
  end

  defp normalize_params(:change_signature, params) do
    %{
      module: normalize_module(params.module),
      function_name: to_atom(params.function_name),
      arity: to_integer(params.arity),
      new_params: params.new_params
    }
  end

  defp normalize_params(:move_function, params) do
    %{
      source_module: normalize_module(params.source_module),
      target_module: normalize_module(params.target_module),
      function_name: to_atom(params.function_name),
      arity: to_integer(params.arity)
    }
  end

  defp normalize_params(:extract_module, params) do
    %{
      source_module: normalize_module(params.source_module),
      new_module: normalize_module(params.new_module),
      functions: params.functions
    }
  end

  defp normalize_params(_, params), do: params

  defp to_integer(val) when is_integer(val), do: val

  defp to_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      _ -> 0
    end
  end

  defp find_affected_files(op, params)
       when op in [:rename_function, :change_signature, :inline_function] do
    mod = params.module
    func = params[:old_name] || params[:function_name] || params[:function]
    arity = params.arity

    case Store.find_node(:function, {mod, func, arity}) do
      nil ->
        {:error, "Function #{mod}.#{func}/#{arity} not found"}

      function_node ->
        def_file = function_node[:file]

        callers = Store.get_incoming_edges({:function, mod, func, arity}, :calls)

        caller_files =
          callers
          |> Enum.map(fn %{from: {:function, m, f, a}} ->
            case Store.find_node(:function, {m, f, a}) do
              nil -> nil
              node -> node[:file]
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        {:ok, [def_file | caller_files] |> Enum.uniq() |> Enum.reject(&is_nil/1)}
    end
  end

  defp find_affected_files(:rename_module, params) do
    case Store.find_node(:module, params.old_name) do
      nil ->
        {:error, "Module #{params.old_name} not found"}

      module_node ->
        def_file = module_node[:file]
        importers = Store.get_incoming_edges({:module, params.old_name}, :imports)

        importer_files =
          importers
          |> Enum.map(fn %{from: {:module, m}} ->
            case Store.find_node(:module, m) do
              nil -> nil
              node -> node[:file]
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        {:ok, [def_file | importer_files] |> Enum.uniq() |> Enum.reject(&is_nil/1)}
    end
  end

  defp find_affected_files(op, params)
       when op in [:extract_function, :convert_visibility, :rename_parameter] do
    case Store.find_node(:module, params.module) do
      nil -> {:error, "Module #{params.module} not found"}
      module_node -> {:ok, [module_node[:file]]}
    end
  end

  defp find_affected_files(:move_function, params) do
    source_file =
      case Store.find_node(:module, params.source_module) do
        nil -> nil
        node -> node[:file]
      end

    target_file =
      case Store.find_node(:module, params.target_module) do
        nil -> derive_file_path(params.target_module)
        node -> node[:file]
      end

    if is_nil(source_file) do
      {:error, "Source module #{params.source_module} not found"}
    else
      {:ok, [source_file, target_file] |> Enum.uniq() |> Enum.reject(&is_nil/1)}
    end
  end

  defp find_affected_files(:extract_module, params) do
    source_file =
      case Store.find_node(:module, params.source_module) do
        nil -> nil
        node -> node[:file]
      end

    new_file = derive_file_path(params.new_module)

    if is_nil(source_file) do
      {:error, "Source module #{params.source_module} not found"}
    else
      {:ok, [source_file, new_file] |> Enum.uniq() |> Enum.reject(&is_nil/1)}
    end
  end

  defp find_affected_files(_, _), do: {:ok, []}

  defp read_files(files, _op, _params) do
    contents =
      Map.new(files, fn file ->
        case File.read(file) do
          {:ok, content} -> {file, content}
          _ -> {file, ""}
        end
      end)

    {:ok, contents}
  end

  defp apply_memory_transforms(op, params, file_contents) do
    case op do
      :rename_function ->
        transformed =
          Map.new(file_contents, fn {path, content} ->
            {:ok, new} =
              Ragex.Editor.Refactor.Elixir.rename_function(
                content,
                params.old_name,
                params.new_name,
                params.arity
              )

            {path, {content, new}}
          end)

        {:ok, transformed}

      :rename_module ->
        transformed =
          Map.new(file_contents, fn {path, content} ->
            {:ok, new} =
              Ragex.Editor.Refactor.Elixir.rename_module(
                content,
                params.old_name,
                params.new_name
              )

            {path, {content, new}}
          end)

        {:ok, transformed}

      :change_signature ->
        signature_changes = parse_new_params(params.new_params, params.arity)

        transformed =
          Map.new(file_contents, fn {path, content} ->
            {:ok, new} =
              Ragex.Editor.Refactor.Elixir.change_signature(
                content,
                :Dummy,
                params.function_name,
                params.arity,
                signature_changes
              )

            {path, {content, new}}
          end)

        {:ok, transformed}

      :inline_function ->
        transformed =
          Map.new(file_contents, fn {path, content} ->
            {:ok, new} =
              Ragex.Editor.Refactor.Elixir.inline_function(
                content,
                :Dummy,
                params.function_name,
                params.arity
              )

            {path, {content, new}}
          end)

        {:ok, transformed}

      :convert_visibility ->
        transformed =
          Map.new(file_contents, fn {path, content} ->
            {:ok, new} =
              Ragex.Editor.Refactor.Elixir.convert_visibility(
                content,
                params.module,
                params.function_name,
                params.arity,
                params.visibility
              )

            {path, {content, new}}
          end)

        {:ok, transformed}

      :rename_parameter ->
        transformed =
          Map.new(file_contents, fn {path, content} ->
            {:ok, new} =
              Ragex.Editor.Refactor.Elixir.rename_parameter(
                content,
                params.module,
                params.function,
                params.arity,
                params.old_param,
                params.new_param
              )

            {path, {content, new}}
          end)

        {:ok, transformed}

      :extract_function ->
        transformed =
          Map.new(file_contents, fn {path, content} ->
            {:ok, new} =
              Ragex.Editor.Refactor.Elixir.extract_function(
                content,
                params.module,
                params.source_function,
                params.source_arity,
                params.new_name,
                {params.line_start, params.line_end}
              )

            {path, {content, new}}
          end)

        {:ok, transformed}

      :move_function ->
        source_file = Store.find_node(:module, params.source_module)[:file]

        target_file =
          case Store.find_node(:module, params.target_module) do
            nil -> derive_file_path(params.target_module)
            node -> node[:file]
          end

        source_content = Map.get(file_contents, source_file, "")
        target_content = Map.get(file_contents, target_file, "")

        {:ok, res} =
          Ragex.Editor.Refactor.Elixir.move_function(
            source_content,
            target_content,
            params.source_module,
            params.target_module,
            params.function_name,
            params.arity
          )

        transformed = %{
          source_file => {source_content, res.source},
          target_file => {target_content, res.target}
        }

        {:ok, transformed}

      :extract_module ->
        source_file = Store.find_node(:module, params.source_module)[:file]
        new_file = derive_file_path(params.new_module)

        source_content = Map.get(file_contents, source_file, "")
        new_content = ""

        functions = parse_functions_list(params.functions)

        {:ok, res} =
          Ragex.Editor.Refactor.Elixir.extract_module(
            source_content,
            params.source_module,
            params.new_module,
            functions
          )

        transformed = %{
          source_file => {source_content, res.source},
          new_file => {new_content, res.target}
        }

        {:ok, transformed}

      _ ->
        {:error, "Unsupported preview operation"}
    end
  end

  defp generate_preview_diffs(transformed_contents) do
    diffs =
      Enum.map(transformed_contents, fn {path, {old_content, new_content}} ->
        {:ok, diff} =
          Ragex.Editor.Diff.generate_diff(old_content, new_content,
            old_file: path,
            new_file: path
          )

        {:ok, html} = Ragex.Editor.Diff.format_diff(diff, :html)

        %{
          file: path,
          html: html,
          additions: diff.stats.additions,
          deletions: diff.stats.deletions
        }
      end)

    {:ok, diffs}
  end

  defp check_operation_conflicts(:rename_function, params) do
    Ragex.Editor.Conflict.check_rename_conflicts(params.module, params.new_name, params.arity)
  end

  defp check_operation_conflicts(:move_function, params) do
    Ragex.Editor.Conflict.check_move_conflicts(
      params.source_module,
      params.target_module,
      params.function_name,
      params.arity
    )
  end

  defp check_operation_conflicts(:extract_module, params) do
    functions = parse_functions_list(params.functions)

    Ragex.Editor.Conflict.check_extract_module_conflicts(
      params.source_module,
      params.new_module,
      functions
    )
  end

  defp check_operation_conflicts(:convert_visibility, params) do
    Ragex.Editor.Conflict.check_visibility_conflicts(
      params.module,
      params.function_name,
      params.arity,
      params.visibility
    )
  end

  defp check_operation_conflicts(_, _params) do
    {:ok,
     %{
       has_conflicts: false,
       conflicts: [],
       stats: %{errors: 0, warnings: 0, infos: 0}
     }}
  end

  defp derive_file_path(module_atom) do
    mod_str = Atom.to_string(module_atom) |> String.replace_prefix("Elixir.", "")

    parts =
      mod_str
      |> String.split(".")
      |> Enum.map(&Macro.underscore/1)

    "lib/" <> Enum.join(parts, "/") <> ".ex"
  end

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

    full =
      if String.starts_with?(module_str, "Elixir.") do
        module_str
      else
        "Elixir." <> module_str
      end

    safe_atom(full)
  end

  defp normalize_module(module_atom) when is_atom(module_atom) do
    normalize_module(Atom.to_string(module_atom))
  end

  defp to_atom(val) when is_atom(val), do: val
  defp to_atom(val) when is_binary(val), do: safe_atom(val)

  defp safe_atom(val) when is_atom(val), do: val

  defp safe_atom(val) when is_binary(val) do
    trimmed = String.trim(val)

    try do
      String.to_existing_atom(trimmed)
    rescue
      ArgumentError -> String.to_atom(trimmed)
    end
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
          {safe_atom(name), String.to_integer(arity_str)}

        [name] ->
          {safe_atom(name), 0}
      end
    end)
  end
end
