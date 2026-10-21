defmodule Rageg.Diagnostics do
  @moduledoc """
  Structured surfacing of *suppressed* errors.

  Much of Rageg is deliberately defensive: a failing optional subsystem (a
  busy dllb pool, an unloaded embedding model, a missing analysis cache) must
  never take a LiveView down, so call sites `rescue`/`catch` and fall back to
  an empty result. The cost is that the *reason* disappears, which makes
  "why is this page empty?" impossible to answer from the logs.

  This module gives those call sites a one-liner that keeps the fallback
  behaviour but records the failure:

      defp fetch_something do
        do_fetch()
      rescue
        e ->
          Rageg.Diagnostics.suppressed(:quality_summary, e)
          []
      end

  Every suppressed error is:

    * logged at `:warning` with the operation label and the formatted
      exception (first occurrence per operation, and then at most once per
      `:window_ms`), so a hot loop cannot flood the log;
    * counted per operation, so the UI can tell the user the app is running
      in a degraded state;
    * exposed through `report/0` and `degraded?/0`.

  Counters live in `:persistent_term`-free ETS owned by this GenServer, so
  reading them from a LiveView is a cheap `:ets.lookup/2` rather than a
  `GenServer.call/2`.

  ## Usage in templates

      <div :if={Rageg.Diagnostics.degraded?()} class="alert alert-warning">
        Some data could not be loaded. See logs for details.
      </div>
  """

  use GenServer

  require Logger

  @table __MODULE__
  @default_window_ms 60_000

  # -- Client API --

  @doc "Starts the diagnostics registry. Started by `Rageg.Application`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a suppressed error for `operation` and returns `fallback`.

  Designed to be used as the last expression of a `rescue`/`catch` clause:

      rescue
        e -> Rageg.Diagnostics.suppressed(:graph_stats, e, %{})
  """
  @spec suppressed(atom() | String.t(), term(), term()) :: term()
  def suppressed(operation, error, fallback \\ nil) do
    record(operation, error)
    fallback
  end

  @doc "Records a suppressed error without returning a value."
  @spec record(atom() | String.t(), term()) :: :ok
  def record(operation, error) do
    # Synchronous on purpose: callers use this immediately before returning a
    # fallback, and tests/UI read the report right after. The work is a single
    # ETS write plus at most one log line, so it is cheap enough to inline.
    GenServer.call(__MODULE__, {:record, normalize(operation), error, self()})
  catch
    :exit, _ -> :ok
  end

  @doc """
  Returns `%{operation => %{count: n, last_reason: String.t(), last_at: DateTime.t()}}`
  for every operation that has failed since boot.
  """
  @spec report() :: %{optional(atom()) => map()}
  def report do
    :ets.tab2list(@table) |> Map.new()
  rescue
    ArgumentError -> %{}
  end

  @doc "True when at least one suppressed error has been recorded."
  @spec degraded?() :: boolean()
  def degraded? do
    :ets.info(@table, :size) not in [0, :undefined]
  rescue
    ArgumentError -> false
  end

  @doc "Number of distinct operations that reported a suppressed error."
  @spec degraded_count() :: non_neg_integer()
  def degraded_count do
    :ets.info(@table, :size)
  rescue
    ArgumentError -> 0
  end

  @doc "Clears all recorded diagnostics (used by the dashboard reset and tests)."
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  catch
    :exit, _ -> :ok
  end

  # -- Server callbacks --

  @impl GenServer
  def init(opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{window_ms: Keyword.get(opts, :window_ms, @default_window_ms)}}
  end

  @impl GenServer
  def handle_call({:record, operation, error, pid}, _from, state) do
    now = System.monotonic_time(:millisecond)

    {count, last_logged_at} =
      case :ets.lookup(@table, operation) do
        [{^operation, entry}] -> {entry.count, entry.last_logged_at}
        [] -> {0, nil}
      end

    count = count + 1
    should_log = is_nil(last_logged_at) or now - last_logged_at >= state.window_ms

    :ets.insert(
      @table,
      {operation,
       %{
         count: count,
         last_reason: describe(error),
         last_at: DateTime.utc_now(),
         last_logged_at: if(should_log, do: now, else: last_logged_at)
       }}
    )

    if should_log do
      Logger.warning(
        "[suppressed] #{operation} failed (#{count}x so far, pid #{inspect(pid)}): " <>
          describe(error)
      )
    end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  # -- Private --

  defp normalize(operation) when is_atom(operation), do: operation

  defp normalize(operation) when is_binary(operation) do
    String.to_existing_atom(operation)
  rescue
    ArgumentError -> :unknown
  end

  defp describe(%{__exception__: true} = exception), do: Exception.message(exception)
  defp describe({kind, reason}), do: "#{kind}: #{inspect(reason, limit: 20)}"
  defp describe(reason), do: inspect(reason, limit: 20)
end
