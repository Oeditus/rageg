defmodule Rageg.Profiles.CoreIngestor do
  @moduledoc """
  One-time ingestion of the Elixir standard library into dllb.

  Runs on first application startup (gated by a sentinel file) to
  ensure that cross-references to `Enum`, `String`, `GenServer`, etc.
  are always available regardless of which project is loaded.

  The sentinel file is `~/.rageg/.core_ingested`. If it exists,
  ingestion is skipped.
  """

  require Logger

  alias Rageg.Profiles.DllbIngestor

  @core_project_tag "elixir_core"

  @doc """
  Runs core ingestion if the sentinel file is missing and dllb is connected.

  This is meant to be called from `Rageg.Profiles.init/1` in a background Task.
  """
  @spec maybe_ingest(String.t()) :: :ok | :already_done | {:error, term()}
  def maybe_ingest(rageg_dir) do
    sentinel = Path.join(rageg_dir, ".core_ingested")

    if File.exists?(sentinel) do
      :already_done
    else
      case find_elixir_lib() do
        {:ok, elixir_lib_path} ->
          Logger.info("First startup: ingesting Elixir core library from #{elixir_lib_path}")

          case DllbIngestor.ingest(elixir_lib_path,
                 project_tag: @core_project_tag,
                 on_progress: &Logger.info("  [core] #{&1}")
               ) do
            {:ok, result} ->
              Logger.info("Elixir core ingested: #{result.files_ok} files, #{result.nodes} nodes")

              Rageg.Dllb.save_ingest_stats(@core_project_tag, result)
              File.mkdir_p!(Path.dirname(sentinel))
              File.write!(sentinel, "ingested at #{DateTime.utc_now()}\n")
              :ok

            {:error, reason} ->
              Logger.warning("Core ingestion failed: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, reason} ->
          Logger.warning("Could not find Elixir source library: #{inspect(reason)}")
          {:error, reason}
      end
    end
  rescue
    e ->
      Logger.warning("Core ingestion error: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  @doc "Returns the project tag used for core library records."
  @spec core_project_tag() :: String.t()
  def core_project_tag, do: @core_project_tag

  # -- Private --

  defp find_elixir_lib do
    # Try the compiled Elixir lib directory (contains .ex source files in some installs)
    # Primary: look for the Elixir source in the install
    candidates = [
      # asdf / mise installs keep source alongside compiled
      Path.join(:code.lib_dir(:elixir), "lib"),
      # Typical system install
      "/usr/local/lib/elixir/lib",
      "/usr/lib/elixir/lib",
      # homebrew
      "/opt/homebrew/lib/elixir/lib"
    ]

    case Enum.find(candidates, &has_ex_files?/1) do
      nil -> {:error, :elixir_source_not_found}
      path -> {:ok, path}
    end
  end

  defp has_ex_files?(dir) do
    File.dir?(dir) &&
      dir
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.any?()
  end
end
