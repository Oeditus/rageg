defmodule RagegWeb.EditorOpener do
  @moduledoc """
  Opens a file at a line in the user's editor.

  The editor is chosen from (in order): `PLUG_EDITOR`, `EDITOR`, then `code`.
  Supports editor commands that take `__FILE__`/`__LINE__` placeholders as well
  as common CLI editors. Previously duplicated in `ChatLive` and `AuditLive`.
  """

  @doc """
  Opens `file_path` at `line` in the configured editor. Returns `:ok` on a
  best-effort basis; failures fall back to `xdg-open` and are otherwise ignored.
  """
  @spec open(String.t() | nil, integer() | String.t() | nil) :: :ok
  def open(file_path, line) when is_binary(file_path) do
    editor = System.get_env("PLUG_EDITOR") || System.get_env("EDITOR") || "code"
    abs_path = Path.expand(file_path)
    line_str = to_string(line || 1)

    cond do
      editor =~ "__FILE__" ->
        cmd_string =
          editor
          |> String.replace("__FILE__", abs_path)
          |> String.replace("__LINE__", line_str)

        case String.split(cmd_string, " ", parts: 2) do
          [prog | args] -> System.cmd(prog, args)
          _ -> :ok
        end

      editor in ["code", "cursor", "vscode"] ->
        System.cmd(editor, ["--goto", "#{abs_path}:#{line_str}"])

      editor in ["subl", "sublime"] ->
        System.cmd(editor, ["#{abs_path}:#{line_str}"])

      true ->
        case String.split(editor, " ") do
          [prog | args] -> System.cmd(prog, args ++ [abs_path])
          _ -> System.cmd("xdg-open", [abs_path])
        end
    end

    :ok
  rescue
    _ ->
      System.cmd("xdg-open", [Path.expand(file_path)])
      :ok
  end

  def open(_file_path, _line), do: :ok
end
