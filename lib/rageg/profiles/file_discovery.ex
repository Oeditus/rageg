defmodule Rageg.Profiles.FileDiscovery do
  @moduledoc """
  Discovers source files in a project directory for dllb ingestion.

  Walks directories recursively, filters by supported extensions,
  and excludes build artifacts. Mirrors the logic from
  `Mix.Tasks.Dllb.Ingest` but is callable as a regular function.
  """

  @extension_to_language %{
    ".ex" => :elixir,
    ".exs" => :elixir,
    ".erl" => :erlang,
    ".hrl" => :erlang,
    ".py" => :python,
    ".rb" => :ruby,
    ".hs" => :haskell
  }

  @excluded_dirs ~w(_build .git .elixir_ls .lexical .dialyzer deps node_modules .hex)

  @doc """
  Discovers all source files under the given path.

  Returns a list of `{absolute_path, language}` tuples, sorted by path.
  """
  @spec discover(String.t()) :: [{String.t(), atom()}]
  def discover(path) do
    abs = Path.expand(path)

    if File.dir?(abs) do
      abs
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.flat_map(&classify/1)
      |> Enum.reject(&excluded?/1)
      |> Enum.uniq_by(fn {p, _} -> p end)
      |> Enum.sort_by(fn {p, _} -> p end)
    else
      classify(abs) |> Enum.reject(&excluded?/1)
    end
  end

  @doc "Returns the number of supported extensions."
  @spec supported_extensions() :: [String.t()]
  def supported_extensions, do: Map.keys(@extension_to_language)

  defp classify(path) do
    case Map.get(@extension_to_language, Path.extname(path)) do
      nil -> []
      lang -> [{path, lang}]
    end
  end

  defp excluded?({path, _lang}) do
    parts = Path.split(path)
    Enum.any?(@excluded_dirs, &(&1 in parts))
  end
end
