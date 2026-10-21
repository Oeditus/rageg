defmodule Rageg.TaskRunner do
  @moduledoc """
  Supervised, cancelable background jobs for LiveViews.

  Historically each LiveView rolled its own `Task.start/1` + `send/2` +
  `Process.monitor/1` combination. That works, but it has three drawbacks:

    1. Jobs are unlinked and unsupervised -- a crash is only noticed if the
       LiveView happens to monitor it, and nothing is logged otherwise.
    2. Jobs are not cancelable in a structured way (callers reach for
       `Process.exit(pid, :kill)`), and the task pid is easy to leak into
       socket assigns after the job already finished.
    3. Jobs orphan when the LiveView disconnects; nothing tells them to stop.

  `Rageg.TaskRunner` centralises the pattern:

      def handle_event("run", _params, socket) do
        {:noreply, Rageg.TaskRunner.start(socket, :analyze, fn -> Analyze.run(path) end)}
      end

      # Results (and crashes) arrive as regular messages:
      def handle_info({:task_result, :analyze, result}, socket), do: ...
      def handle_info({:task_error, :analyze, reason}, socket), do: ...

  ## Messages

  For a job tagged `tag`, the LiveView receives exactly one of:

    * `{:task_result, tag, result}` -- the fun returned normally.
    * `{:task_error, tag, reason}` -- the fun raised, threw, or exited.

  Both are always sent, so a LiveView never has to reason about monitors to
  know that a job finished.

  ## Cancellation

  `cancel/2` kills the job's process (and its monitor) and returns `:ok` /
  `{:error, :not_found}`. Because the job is supervised by
  `Rageg.TaskSupervisor`, a kill is contained and logged rather than taking
  anything else down.

  ## Lifecycle

  Jobs are tracked per LiveView pid. When the LiveView terminates (navigates
  away, disconnects), every job it started is cancelled automatically, so no
  work is left running for a page nobody is looking at.
  """

  use GenServer

  require Logger

  @table __MODULE__
  @supervisor Rageg.TaskSupervisor

  @type tag :: term()
  @type job :: %{
          tag: tag(),
          pid: pid(),
          ref: reference(),
          owner: pid(),
          started_at: integer()
        }

  # -- Client API --

  @doc """
  Starts the job registry. Started by `Rageg.Application`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts `fun` as a supervised background job owned by the LiveView `socket`.

  The job's return value is delivered to the LiveView as
  `{:task_result, tag, result}`; a crash as `{:task_error, tag, reason}`.

  Returns the updated socket with the job tag assigned to `assign_key`
  (default `:job_tag`) so templates can render a spinner/cancel button.

  ## Options

    * `:assign_key` - socket assign that receives the tag (default `:job_tag`)
  """
  @spec start(Phoenix.LiveView.Socket.t(), tag(), (-> term()), keyword()) ::
          Phoenix.LiveView.Socket.t()
  def start(socket, tag, fun, opts \\ []) when is_function(fun, 0) do
    owner = self()
    assign_key = Keyword.get(opts, :assign_key, :job_tag)

    {:ok, pid} = Task.Supervisor.start_child(@supervisor, fn -> run_job(owner, tag, fun) end)

    ref = Process.monitor(pid)
    GenServer.cast(__MODULE__, {:track, owner, tag, pid, ref})

    Phoenix.Component.assign(socket, assign_key, tag)
  end

  @doc """
  Cancels the job identified by `tag` for the calling process.

  Returns `:ok` when a job was cancelled, `{:error, :not_found}` otherwise.
  """
  @spec cancel(tag()) :: :ok | {:error, :not_found}
  def cancel(tag) do
    GenServer.call(__MODULE__, {:cancel, self(), tag})
  end

  @doc "Lists jobs currently owned by the calling process."
  @spec jobs() :: [job()]
  def jobs do
    GenServer.call(__MODULE__, {:jobs, self()})
  end

  @doc "Lists jobs for every owner (diagnostics)."
  @spec all_jobs() :: [job()]
  def all_jobs do
    GenServer.call(__MODULE__, :all_jobs)
  end

  # -- Server callbacks --

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  @impl GenServer
  def handle_cast({:track, owner, tag, pid, ref}, state) do
    :ets.insert(@table, {ref, %{tag: tag, pid: pid, ref: ref, owner: owner, started_at: now()}})
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:cancel, owner, tag}, _from, state) do
    case find(owner, tag) do
      nil ->
        {:reply, {:error, :not_found}, state}

      job ->
        Process.demonitor(job.ref, [:flush])
        :ets.delete(@table, job.ref)
        Process.exit(job.pid, :kill)
        {:reply, :ok, state}
    end
  end

  def handle_call({:jobs, owner}, _from, state) do
    jobs = for {_ref, job} <- :ets.tab2list(@table), job.owner == owner, do: job
    {:reply, jobs, state}
  end

  def handle_call(:all_jobs, _from, state) do
    {:reply, for({_ref, job} <- :ets.tab2list(@table), do: job), state}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    # Either the job finished (its result message was already sent) or its
    # owner went away. Either way the entry is no longer needed.
    :ets.delete(@table, ref)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -- Private --

  # Runs the job and always reports back, translating every failure mode into
  # a single `{:task_error, tag, reason}` message.
  defp run_job(owner, tag, fun) do
    result = fun.()
    send(owner, {:task_result, tag, result})
  rescue
    exception ->
      Logger.error(
        "TaskRunner job #{inspect(tag)} crashed: " <>
          Exception.format(:error, exception, __STACKTRACE__)
      )

      send(owner, {:task_error, tag, {:error, exception}})
  catch
    kind, reason ->
      Logger.error("TaskRunner job #{inspect(tag)} aborted: #{inspect({kind, reason})}")
      send(owner, {:task_error, tag, {kind, reason}})
  end

  defp find(owner, tag) do
    Enum.find_value(:ets.tab2list(@table), fn {_ref, job} ->
      if job.owner == owner and job.tag == tag, do: job
    end)
  end

  defp now, do: System.monotonic_time(:millisecond)
end
