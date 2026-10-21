defmodule Rageg.Atom do
  @moduledoc """
  Safe helpers for converting user-supplied strings into atoms.

  Elixir atoms are not garbage collected, so turning arbitrary user input
  into atoms with `String.to_atom/1` is a memory-exhaustion risk (the project
  `AGENTS.md` forbids it). This module provides two explicit paths:

    * `existing/1` / `existing!/1` -- for references that must already exist
      (module names, existing function names, parameter names, plugin ids).
      Unknown values return `{:error, :unknown_atom}` (or raise) instead of
      silently creating an atom.

    * `new/1` / `new!/1` -- for values that are legitimately new (a renamed
      function/parameter, a new module). The string is validated to be a
      well-formed identifier or dotted module path before a single atom is
      created, so garbage input (spaces, control characters, oversized names)
      is rejected rather than leaking an atom.
  """

  # Identifiers: foo, foo?, foo!, foo_bar. Module paths: MyApp.Repo, Elixir.MyApp.
  @valid_name ~r/^(?:Elixir\.)?[A-Za-z_][A-Za-z0-9_.?!]*$/
  @max_length 255

  @doc """
  Returns `{:ok, atom}` if the atom already exists, otherwise `{:error, :unknown_atom}`.
  """
  @spec existing(atom() | String.t()) :: {:ok, atom()} | {:error, :unknown_atom}
  def existing(value) when is_atom(value), do: {:ok, value}

  def existing(value) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> {:error, :unknown_atom}
  end

  @doc """
  Like `existing/1` but raises `ArgumentError` for unknown atoms.

  Callers are expected to wrap this in a `rescue` that reports a friendly
  error (the refactoring/impact context modules already do this).
  """
  @spec existing!(atom() | String.t()) :: atom()
  def existing!(value) when is_atom(value), do: value
  def existing!(value) when is_binary(value), do: String.to_existing_atom(value)

  @doc """
  Returns `{:ok, atom}` for a validated new identifier/module path, otherwise
  `{:error, :invalid_name}`. Only well-formed, bounded names ever create atoms.
  """
  @spec new(String.t()) :: {:ok, atom()} | {:error, :invalid_name}
  def new(value) when is_binary(value) do
    trimmed = String.trim(value)

    if valid_name?(trimmed) do
      {:ok, String.to_atom(trimmed)}
    else
      {:error, :invalid_name}
    end
  end

  @doc """
  Like `new/1` but raises `ArgumentError` for invalid names.
  """
  @spec new!(String.t()) :: atom()
  def new!(value) when is_binary(value) do
    case new(value) do
      {:ok, atom} -> atom
      {:error, :invalid_name} -> raise ArgumentError, "invalid atom name: #{inspect(value)}"
    end
  end

  @doc "Returns true when the string is a well-formed identifier or module path."
  @spec valid_name?(String.t()) :: boolean()
  def valid_name?(value) when is_binary(value) do
    byte_size(value) > 0 and byte_size(value) <= @max_length and
      Regex.match?(@valid_name, value)
  end
end
