defmodule Mix.Tasks.Rageg.Reset do
  @shortdoc "Wipe all graph, embedding, AI cache, and dllb state for a clean test run"

  @moduledoc """
  Resets rageg to a completely clean state.

  Clears the following in order:

    1. Persisted stats file (`~/.rageg/.dllb_stats.json`)
    2. Per-file ingest-cache manifests (`~/.rageg/.ingest_cache/`)
    3. All saved project profiles (`~/.rageg/profiles/`) and active state
    4. dllb `ast_node`, `_edge_idx`, and all RELATE edge tables
    5. Ragex in-memory knowledge graph (ETS nodes + edges + embeddings)
    6. Ragex AI cache and embedding persistence cache
    7. Ragex analysis quality cache
    8. Ragex AI usage counters

  Steps 4-8 require the respective applications to be running or reachable.
  Failures are reported but do not stop subsequent steps.

  ## Usage

      mix rageg.reset

  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("Resetting rageg state...")

    # Start the apps needed to talk to dllb and ragex.
    {:ok, _} = Application.ensure_all_started(:rageg)

    step("Clearing dllb tables + stats file", fn ->
      Rageg.Dllb.clear_all!()
    end)

    step("Clearing Ragex knowledge graph", fn ->
      Ragex.Graph.Store.clear()
    end)

    step("Clearing Ragex AI cache", fn ->
      Ragex.AI.Cache.clear()
    end)

    step("Clearing Ragex embedding persistence cache", fn ->
      Ragex.Embeddings.Persistence.clear(:all)
    end)

    step("Clearing Ragex analysis cache", fn ->
      Ragex.Analysis.Quality.clear_all()
    end)

    step("Resetting Ragex AI usage counters", fn ->
      Ragex.AI.Usage.reset_stats()
    end)

    Mix.shell().info("Done. State is clean.")
  end

  defp step(label, fun) do
    Mix.shell().info("  #{label}...")

    fun.()
  rescue
    e ->
      Mix.shell().error("  FAILED: #{Exception.message(e)}")
  end
end
