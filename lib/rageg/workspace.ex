defmodule Rageg.Workspace do
  @moduledoc """
  Allowlist of directories Rageg is permitted to ingest, analyse, or refactor.

  Rageg is a powerful local tool: it walks directories, parses them, rewrites
  files during refactors, and can be pointed at any path a user types. On a
  single-developer machine that is fine; on a shared box (or behind a reverse
  proxy) it means anyone who can reach the UI can read and rewrite anything the
  BEAM user can.

  This module implements the "trusted workspace" half of that defence: a list
  of allowed root directories, configured with

      config :rageg, :allowed_roots, ["~/code", "/srv/repos"]

  and enforced by `allowed?/1` at the entry points that accept a user-supplied
  path (profile creation/switching, analysis, assessment, MCP tool arguments).

  ## Defaults

  When `:allowed_roots` is not configured the allowlist is **disabled** and
  every path is allowed -- local development keeps working unchanged. Set it to
  a non-empty list to lock the app down; a common team setup is to allow the
  user's home directory only:

      config :rageg, :allowed_roots, ["~"]

  ## Semantics

  A path is allowed when, after expanding `~` and symlinks, it is equal to or
  nested under one of the configured roots. `..` traversal is resolved before
  the check, so `/srv/repos/../../etc` is rejected.
  """

  @doc """
  Returns the configured allowlist as expanded absolute paths.

  An empty list means "no restriction".
  """
  @spec allowed_roots() :: [String.t()]
  def allowed_roots do
    :rageg
    |> Application.get_env(:allowed_roots, [])
    |> List.wrap()
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
  end

  @doc "True when the allowlist is active (at least one root configured)."
  @spec enforced?() :: boolean()
  def enforced?, do: allowed_roots() != []

  @doc """
  Returns `:ok` when `path` may be used, otherwise `{:error, :path_not_allowed}`.

  A path that does not exist yet (e.g. a not-yet-created target of a refactor)
  is checked against its parent directory.
  """
  @spec check(String.t() | nil) :: :ok | {:error, :path_not_allowed}
  def check(path)

  def check(nil), do: {:error, :path_not_allowed}

  def check(path) when is_binary(path) do
    roots = allowed_roots()

    if roots == [] do
      :ok
    else
      real = real_path(path)

      if Enum.any?(roots, &within?(real, &1)) do
        :ok
      else
        {:error, :path_not_allowed}
      end
    end
  end

  @doc "Convenience predicate version of `check/1`."
  @spec allowed?(String.t() | nil) :: boolean()
  def allowed?(path), do: check(path) == :ok

  @doc """
  Human-readable message for a rejected path, suitable for the UI.
  """
  @spec rejection_message(String.t()) :: String.t()
  def rejection_message(path) do
    "Path #{path} is outside the trusted workspace. " <>
      "Allowed roots: #{Enum.join(allowed_roots(), ", ")}"
  end

  # -- Private --

  # Resolves symlinks for the deepest existing ancestor, so a symlinked root
  # and a symlinked path compare correctly. Non-existent tails are appended
  # verbatim (the caller is checking intent, not existence).
  defp real_path(path) do
    expanded = Path.expand(path)

    case resolve_existing(expanded) do
      {:ok, real} -> real
      :error -> expanded
    end
  end

  defp resolve_existing(path) do
    case File.read_link(path) do
      {:ok, _} ->
        case File.stat(path) do
          {:ok, _} -> {:ok, realpath(path)}
          _ -> :error
        end

      _ ->
        case File.stat(path) do
          {:ok, _} -> {:ok, realpath(path)}
          _ -> resolve_parent(path)
        end
    end
  end

  defp resolve_parent(path) do
    parent = Path.dirname(path)

    if parent == path do
      :error
    else
      case resolve_existing(parent) do
        {:ok, real_parent} -> {:ok, Path.join(real_parent, Path.basename(path))}
        :error -> :error
      end
    end
  end

  # `:file.read_link_all/1` resolves a symlink chain; fall back to the input
  # when the platform/filesystem does not support it.
  defp realpath(path) do
    case :file.read_link_all(String.to_charlist(path)) do
      {:ok, resolved} -> List.to_string(resolved)
      _ -> path
    end
  end

  defp within?(path, root) do
    path == root or String.starts_with?(path, root <> "/")
  end
end
