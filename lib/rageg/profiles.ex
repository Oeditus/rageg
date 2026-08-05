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
      Task.start(fn ->
        try do
          Ragex.Graph.Store.load_project(active_profile.path)
          watch_directory_safely(active_profile.path)
        rescue
          _ -> :ok
        end
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
      profile = Profile.new(abs_path, name)

      case save_profile(profile, state.profiles_dir) do
        :ok ->
          # If no active profile exists yet, make this one active
          new_active =
            if state.active == nil do
              save_active_profile_id(profile.id, state.profiles_dir)

              Task.start(fn ->
                try do
                  Ragex.Graph.Store.load_project(profile.path)
                  watch_directory_safely(profile.path)
                rescue
                  _ -> :ok
                end
              end)

              Phoenix.PubSub.broadcast(Rageg.PubSub, @topic, {:profile_switched, profile})
              profile
            else
              state.active
            end

          {:reply, {:ok, profile}, %{state | active: new_active}}

        error ->
          {:reply, error, state}
      end
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

              Task.start(fn ->
                try do
                  Ragex.Graph.Store.load_project(next_p.path)
                  watch_directory_safely(next_p.path)
                rescue
                  _ -> :ok
                end
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

  def handle_call({:switch, id, opts}, _from, state) do
    on_progress = Keyword.get(opts, :on_progress, fn _ -> :ok end)

    case find_profile(id, state.profiles_dir) do
      nil ->
        {:reply, {:error, :profile_not_found}, state}

      profile ->
        # Switch in-memory graph, vector store, and file-tracker state to target project
        Ragex.Graph.Store.load_project(profile.path)

        # Watch active project directory for incremental updates when files change
        watch_directory_safely(profile.path)

        # Ingest into dllb (idempotent upserts)
        if dllb_connected?() do
          DllbIngestor.ingest(profile.path,
            project_tag: profile.dllb_project_tag,
            on_progress: on_progress
          )
        else
          on_progress.("dllb not connected, skipping ingestion")
        end

        # Mark as ingested and save
        updated = Profile.mark_ingested(profile)
        save_profile(updated, state.profiles_dir)
        save_active_profile_id(updated.id, state.profiles_dir)

        # Broadcast
        Phoenix.PubSub.broadcast(Rageg.PubSub, @topic, {:profile_switched, updated})
        on_progress.("Profile active: #{updated.name}")

        {:reply, {:ok, updated}, %{state | active: updated}}
    end
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
      fn p -> p.last_ingested_at || p.created_at || "" end,
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
            [Profile.from_json(:json.decode(json))]
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
    json = profile |> Map.from_struct() |> :json.encode() |> IO.iodata_to_binary()
    File.write(file, json)
  end

  defp dllb_connected? do
    Application.get_env(:dllb, :enabled, false) &&
      match?({:ok, _}, Dllb.query("SELECT 1"))
  rescue
    _ -> false
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
