defmodule Rageg.Profiles.IngestCache do
  @moduledoc """
  Tracks per-file modification state to avoid redundant dllb ingestion.

  Each project tag gets its own manifest at
  `~/.rageg/.ingest_cache/<project_tag>.json` containing a map of
  `file_path => %{"mtime" => epoch_seconds, "size" => bytes}`.

  Before ingestion, the caller asks `stale/2` which returns only the
  files that are new or changed since the last recorded ingestion.
  After a successful run, `update/2` persists the new snapshot.
  """

  @cache_dir "~/.rageg/.ingest_cache"

  @type file_entry :: {String.t(), atom()}
  @type fingerprint :: %{String.t() => %{String.t() => integer()}}

  # -- Public --

  @doc """
  Filters a list of `{path, language}` tuples to only those whose
  mtime or size differs from the cached manifest for `project_tag`.

  Returns `{stale_files, cached_count}` where `cached_count` is the
  number of files that were skipped (cache hit).
  """
  @spec stale(String.t(), [{String.t(), atom()}]) ::
          {stale :: [{String.t(), atom()}], cached :: non_neg_integer()}
  def stale(project_tag, files) do
    manifest = load_manifest(project_tag)

    {stale, cached} =
      Enum.reduce(files, {[], 0}, fn {path, _lang} = entry, {stale_acc, cached_acc} ->
        case Map.get(manifest, path) do
          nil ->
            {[entry | stale_acc], cached_acc}

          cached_fp ->
            if file_changed?(path, cached_fp) do
              {[entry | stale_acc], cached_acc}
            else
              {stale_acc, cached_acc + 1}
            end
        end
      end)

    {Enum.reverse(stale), cached}
  end

  @doc """
  Snapshots the current mtime+size for every file in `files` and
  persists it as the manifest for `project_tag`.

  Should be called after a successful ingestion run.
  """
  @spec update(String.t(), [{String.t(), atom()}]) :: :ok | {:error, term()}
  def update(project_tag, files) do
    manifest =
      Map.new(files, fn {path, _lang} ->
        {path, fingerprint(path)}
      end)

    save_manifest(project_tag, manifest)
  end

  @doc """
  Removes the cached manifest for a project tag.
  Next ingestion will process all files.
  """
  @spec invalidate(String.t()) :: :ok
  def invalidate(project_tag) do
    path = manifest_path(project_tag)
    File.rm(path)
    :ok
  end

  # -- Private --

  defp manifest_path(project_tag) do
    safe = String.replace(project_tag, ~r/[^a-zA-Z0-9_\-]/, "_")
    Path.expand(@cache_dir) |> Path.join("#{safe}.json")
  end

  defp load_manifest(project_tag) do
    path = manifest_path(project_tag)

    case File.read(path) do
      {:ok, json} -> Jason.decode!(json)
      _ -> %{}
    end
  rescue
    _ -> %{}
  end

  defp save_manifest(project_tag, manifest) do
    path = manifest_path(project_tag)
    File.mkdir_p!(Path.dirname(path))

    case Jason.encode(manifest, pretty: true) do
      {:ok, json} -> File.write(path, json)
      error -> error
    end
  end

  defp fingerprint(path) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime, size: size}} ->
        %{"mtime" => mtime, "size" => size}

      _ ->
        %{"mtime" => 0, "size" => 0}
    end
  end

  defp file_changed?(path, cached) do
    current = fingerprint(path)
    current["mtime"] != cached["mtime"] or current["size"] != cached["size"]
  end
end
