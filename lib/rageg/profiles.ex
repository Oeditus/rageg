defmodule Rageg.Profiles do
  @moduledoc """
  Manages project profiles and the active project state.

  Profiles are JSON files in `~/.rageg/profiles/`. The GenServer holds
  the currently active profile and orchestrates switching between
  projects (triggering dllb ingestion and PubSub broadcasts).

  ## PubSub

  Broadcasts `{:profile_switched, profile}` on the `"profiles"` topic
  whenever the active profile changes. Broadcasts `{:profile_switched, nil}`
  when all profiles are cleared.
  """

  use GenServer

  alias Rageg.Profile
  alias Rageg.Profiles.DllbIngestor
  alias Ragex.Dllb.ProjectManager, as: DllbProjectManager
  alias Ragex.Embeddings.Bumblebee, as: EmbeddingBumblebee
  alias Ragex.Graph.Store, as: GraphStore

  @topic "profiles"

  # -- Client API --

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the PubSub topic for profile events."
  @spec topic() :: String.t()
  def topic, do: @topic

  @doc "Returns the currently active profile, or nil."
  @spec active() :: Profile.t() | nil
  def active do
    GenServer.call(__MODULE__, :active)
  catch
    :exit, _ -> nil
  end

  @doc "Lists all saved profiles."
  @spec list() :: [Profile.t()]
  def list do
    GenServer.call(__MODULE__, :list)
  catch
    :exit, _ -> []
  end

  @doc "Gets a profile by ID."
  @spec get(String.t()) :: Profile.t() | nil
  def get(id) do
    GenServer.call(__MODULE__, {:get, id})
  catch
    :exit, _ -> nil
  end

  @doc "Creates a new profile from a directory path and optional display name."
  @spec create(String.t(), String.t() | nil, timeout()) :: {:ok, Profile.t()} | {:error, term()}
  def create(path, name \\ nil, timeout \\ :infinity) do
    GenServer.call(__MODULE__, {:create, path, name}, timeout)
  end

  @doc "Deletes a profile by ID."
  @spec delete(String.t(), timeout()) :: :ok | {:error, term()}
  def delete(id, timeout \\ :infinity) do
    GenServer.call(__MODULE__, {:delete, id}, timeout)
  end

  @doc """
  Deletes all saved profiles and resets the active profile to nil.

  Removes every `.json` file in the profiles directory, clears the
  in-memory active profile, and broadcasts `{:profile_switched, nil}` so
  connected LiveViews update their UI immediately.
  """
  @spec clear_all!(timeout()) :: :ok
  def clear_all!(timeout \\ :infinity) do
    GenServer.call(__MODULE__, :clear_all, timeout)
  catch
    :exit, _ -> :ok
  end

  @doc """
  Switches to a profile by ID.

  Triggers dllb ingestion for the profile's project directory, sets
  the profile as active, and broadcasts the change on PubSub.

  ## Options

    * `:on_progress` - `(String.t() -> :ok)` callback for progress messages
  """
  @spec switch(String.t(), keyword()) :: {:ok, Profile.t()} | {:error, term()}
  def switch(id, opts \\ []) do
    GenServer.call(__MODULE__, {:switch, id, opts}, :infinity)
  end

  # -- Server Callbacks --

  @impl GenServer
  def init(_opts) do
    dir = profiles_dir()
    File.mkdir_p!(dir)

    all_profiles = load_all_profiles(dir)
    active_profile = restore_active_profile(dir, all_profiles)

    if active_profile do
      start_background(fn ->
        activate_project(active_profile, fn _ -> :ok end)
      end)
    end

    state = %{
      active: active_profile,
      profiles_dir: dir
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:active, _from, state) do
    {:reply, state.active, state}
  end

  def handle_call(:list, _from, state) do
    {:reply, load_all_profiles(state.profiles_dir), state}
  end

  def handle_call({:get, id}, _from, state) do
    profile =
      state.profiles_dir
      |> load_all_profiles()
      |> Enum.find(&(&1.id == id))

    {:reply, profile, state}
  end

  def handle_call({:create, path, name}, _from, state) do
    abs_path = Path.expand(path)

    if File.dir?(abs_path) do
      all_profiles = load_all_profiles(state.profiles_dir)
      existing = Enum.find(all_profiles, &(&1.path == abs_path))

      profile =
        if existing do
          if name && name != "" && existing.name != name do
            updated = %{existing | name: name}
            save_profile(updated, state.profiles_dir)
            updated
          else
            existing
          end
        else
          new_p = Profile.new(abs_path, name)
          save_profile(new_p, state.profiles_dir)
          new_p
        end

      # If no active profile exists yet, make this one active
      new_active =
        if state.active == nil do
          save_active_profile_id(profile.id, state.profiles_dir)

          start_background(fn ->
            activate_project(profile, fn _ -> :ok end)
            ready = Profile.mark_ingested(profile)
            save_profile(ready, state.profiles_dir)
            Phoenix.PubSub.broadcast(Rageg.PubSub, @topic, {:profile_switched, ready})
          end)

          Phoenix.PubSub.broadcast(Rageg.PubSub, @topic, {:profile_switched, profile})
          profile
        else
          state.active
        end

      {:reply, {:ok, profile}, %{state | active: new_active}}
    else
      {:reply, {:error, "Directory does not exist: #{abs_path}"}, state}
    end
  end

  def handle_call({:delete, id}, _from, state) do
    file = Path.join(state.profiles_dir, "#{id}.json")

    case File.rm(file) do
      :ok ->
        all_profiles = load_all_profiles(state.profiles_dir)

        new_active =
          if state.active && state.active.id == id do
            next_p = latest_profile(all_profiles)

            if next_p do
              save_active_profile_id(next_p.id, state.profiles_dir)

              start_background(fn ->
                activate_project(next_p, fn _ -> :ok end)
                ready = Profile.mark_ingested(next_p)
                save_profile(ready, state.profiles_dir)
                Phoenix.PubSub.broadcast(Rageg.PubSub, @topic, {:profile_switched, ready})
              end)

              next_p
            else
              clear_active_profile_file(state.profiles_dir)
              nil
            end
          else
            state.active
          end

        if state.active != new_active do
          Phoenix.PubSub.broadcast(Rageg.PubSub, @topic, {:profile_switched, new_active})
        end

        {:reply, :ok, %{state | active: new_active}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:clear_all, _from, state) do
    state.profiles_dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.each(&File.rm!/1)

    clear_active_profile_file(state.profiles_dir)

    Phoenix.PubSub.broadcast(Rageg.PubSub, @topic, {:profile_switched, nil})

    {:reply, :ok, %{state | active: nil}}
  end

  def handle_call({:switch, id, opts}, from, state) do
    on_progress = Keyword.get(opts, :on_progress, fn _ -> :ok end)

    case find_profile(id, state.profiles_dir) do
      nil ->
        {:reply, {:error, :profile_not_found}, state}

      profile ->
        indexing_profile = Profile.mark_indexing(profile)
        save_profile(indexing_profile, state.profiles_dir)
        save_active_profile_id(indexing_profile.id, state.profiles_dir)

        Phoenix.PubSub.broadcast(Rageg.PubSub, @topic, {:profile_switched, indexing_profile})

        # Run the (potentially minutes-long) activation off the GenServer so it
        # can keep servicing list/get/create/delete calls. The caller still
        # blocks until `GenServer.reply/2` fires (from the :switch_finished
        # cast), preserving the synchronous `switch/2` contract.
        dir = state.profiles_dir

        start_background(fn ->
          switch_activate(indexing_profile, dir, on_progress, from)
        end)

        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast({:switch_finished, from, reply, profile}, state) do
    GenServer.reply(from, reply)
    {:noreply, %{state | active: profile}}
  end

  # Runs the full per-project activation pipeline. Any failure -- including a
  # process exit (e.g. a `GenServer.call` timeout against the dllb
  # ProjectManager while it is busy bringing up a project's server) -- is
  # caught and returned as `{:error, message}` so the caller can degrade
  # gracefully instead of crashing the Profiles GenServer and wedging the UI.
  defp activate_project(%Profile{} = profile, on_progress) do
    do_activate_project(profile, on_progress)
  rescue
    e ->
      activation_failure(on_progress, Exception.message(e))
  catch
    :exit, reason ->
      activation_failure(on_progress, "interrupted: #{inspect(reason)}")

    :throw, value ->
      activation_failure(on_progress, "aborted: #{inspect(value)}")
  end

  defp activation_failure(on_progress, message) do
    on_progress.("Activation notice: #{message}")
    {:error, message}
  end

  # Runs the activation pipeline for a switch, always replying exactly once via
  # the :switch_finished cast so the caller never blocks forever if something
  # unexpected raises.
  defp switch_activate(indexing_profile, dir, on_progress, from) do
    {status_profile, reply} =
      case activate_project(indexing_profile, on_progress) do
        :ok ->
          ready_profile = Profile.mark_ingested(indexing_profile)
          save_profile(ready_profile, dir)
          on_progress.("Profile active: #{ready_profile.name}")
          {ready_profile, {:ok, ready_profile}}

        {:error, reason} ->
          failed_profile = %{indexing_profile | status: "error"}
          save_profile(failed_profile, dir)
          on_progress.("Profile activation failed: #{inspect(reason)}")
          {failed_profile, {:error, reason}}
      end

    Phoenix.PubSub.broadcast(Rageg.PubSub, @topic, {:profile_switched, status_profile})
    GenServer.cast(__MODULE__, {:switch_finished, from, reply, status_profile})
  rescue
    e ->
      failed_profile = %{indexing_profile | status: "error"}
      safe_save_profile(failed_profile, dir)
      Phoenix.PubSub.broadcast(Rageg.PubSub, @topic, {:profile_switched, failed_profile})

      GenServer.cast(
        __MODULE__,
        {:switch_finished, from, {:error, Exception.message(e)}, failed_profile}
      )
  catch
    kind, reason ->
      failed_profile = %{indexing_profile | status: "error"}
      safe_save_profile(failed_profile, dir)

      GenServer.cast(
        __MODULE__,
        {:switch_finished, from, {:error, "#{kind}: #{inspect(reason)}"}, failed_profile}
      )
  end

  defp safe_save_profile(profile, dir) do
    save_profile(profile, dir)
  rescue
    _ -> :ok
  end

  # Prefer the unlinked Task.Supervisor so a crashing background job cannot take
  # down the Profiles GenServer.
  defp start_background(fun) do
    if Process.whereis(Rageg.TaskSupervisor) do
      Task.Supervisor.start_child(Rageg.TaskSupervisor, fun)
    else
      Task.start(fun)
    end
  end

  defp do_activate_project(%Profile{} = profile, on_progress) do
    # 1. Set environment variables to project path without altering global CWD
    if File.dir?(profile.path) do
      System.put_env("RAGEX_PROJECT", profile.path)
      System.put_env("RAGEX_AUTO_ANALYZE", profile.path)
    end

    # 2. Configure per-project dllb mode & initialize dllb for this project
    on_progress.("Initializing per-project dllb server...")
    Application.put_env(:ragex, :dllb_mode, :per_project)
    Application.put_env(:dllb, :enabled, true)

    if Code.ensure_loaded?(DllbProjectManager) and
         Process.whereis(DllbProjectManager) do
      case DllbProjectManager.set_active_project(profile.path) do
        :ok ->
          on_progress.("Per-project dllb active: #{profile.path}")

        {:error, reason} ->
          on_progress.("per-project dllb notice: #{inspect(reason)}")
      end
    end

    # 3. Load & index project with Ragex
    on_progress.("Indexing project files with Ragex...")
    GraphStore.load_project(profile.path)
    watch_directory_safely(profile.path)

    # 4. Ingest graph into per-project dllb
    if dllb_connected?() do
      on_progress.("Ingesting graph into per-project dllb...")

      DllbIngestor.ingest(profile.path,
        project_tag: profile.dllb_project_tag,
        on_progress: on_progress
      )
    end

    # 5. Index embeddings via Bumblebee if available
    if Code.ensure_loaded?(EmbeddingBumblebee) and EmbeddingBumblebee.available?() do
      on_progress.("Indexing Bumblebee embeddings...")
      wait_for_bumblebee_ready()
    end

    on_progress.("Project ready")
    :ok
  end

  defp wait_for_bumblebee_ready(deadline \\ System.monotonic_time(:millisecond) + 3_000) do
    if EmbeddingBumblebee.ready?() or System.monotonic_time(:millisecond) >= deadline do
      :ok
    else
      Process.sleep(50)
      wait_for_bumblebee_ready(deadline)
    end
  rescue
    _ -> :ok
  end

  # -- Private --

  defp profiles_dir do
    Application.get_env(:rageg, :profiles_dir, "~/.rageg/profiles")
    |> Path.expand()
  end

  defp restore_active_profile(dir, all_profiles) do
    active_file = active_profile_file(dir)

    target_profile =
      if File.exists?(active_file) do
        case File.read(active_file) do
          {:ok, content} ->
            id = String.trim(content)
            Enum.find(all_profiles, &(&1.id == id))

          _ ->
            nil
        end
      else
        nil
      end

    target_profile || latest_profile(all_profiles)
  end

  defp latest_profile([]) do
    nil
  end

  defp latest_profile(profiles) do
    Enum.max_by(
      profiles,
      fn p ->
        last = if p.last_ingested_at != "nil", do: p.last_ingested_at, else: nil
        last || p.created_at || ""
      end,
      fn -> nil end
    )
  end

  defp active_profile_file(dir) do
    Path.join(dir, ".active_profile")
  end

  defp save_active_profile_id(id, dir) do
    File.write!(active_profile_file(dir), id)
  rescue
    _ -> :ok
  end

  defp clear_active_profile_file(dir) do
    File.rm(active_profile_file(dir))
  rescue
    _ -> :ok
  end

  defp load_all_profiles(dir) do
    dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.flat_map(fn file ->
      case File.read(file) do
        {:ok, json} ->
          try do
            case Jason.decode(json) do
              {:ok, map} -> [Profile.from_json(map)]
              _ -> []
            end
          rescue
            _ -> []
          end

        _ ->
          []
      end
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp find_profile(id, dir) do
    dir
    |> load_all_profiles()
    |> Enum.find(&(&1.id == id))
  end

  defp save_profile(%Profile{} = profile, dir) do
    file = Path.join(dir, "#{profile.id}.json")

    File.write(file, Jason.encode!(Map.from_struct(profile)))
  end

  defp dllb_connected? do
    Rageg.Dllb.connected?()
  end

  defp watch_directory_safely(path) do
    if Mix.env() != :test do
      Ragex.Watcher.watch_directory(path)
    end
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end
end
