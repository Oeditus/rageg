defmodule Rageg.Profiles do
  @moduledoc """
  Manages project profiles and the active project state.

  Profiles are JSON files in `~/.rageg/profiles/`. The GenServer holds
  the currently active profile and orchestrates switching between
  projects (triggering dllb ingestion and PubSub broadcasts).

  On first startup, automatically ingests the Elixir core library
  if a dllb server is connected and the sentinel file is missing.

  ## PubSub

  Broadcasts `{:profile_switched, profile}` on the `"profiles"` topic
  whenever the active profile changes.
  """

  use GenServer

  alias Rageg.Profile
  alias Rageg.Profiles.{CoreIngestor, DllbIngestor}

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
  @spec create(String.t(), String.t() | nil) :: {:ok, Profile.t()} | {:error, term()}
  def create(path, name \\ nil) do
    GenServer.call(__MODULE__, {:create, path, name})
  end

  @doc "Deletes a profile by ID."
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(id) do
    GenServer.call(__MODULE__, {:delete, id})
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

    state = %{
      active: nil,
      profiles_dir: dir,
      rageg_dir: rageg_base_dir()
    }

    # Trigger core ingestion in background on first startup
    rageg_dir = state.rageg_dir

    Task.start(fn ->
      if dllb_connected?() do
        CoreIngestor.maybe_ingest(rageg_dir)
      end
    end)

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
        :ok -> {:reply, {:ok, profile}, state}
        error -> {:reply, error, state}
      end
    else
      {:reply, {:error, "Directory does not exist: #{abs_path}"}, state}
    end
  end

  def handle_call({:delete, id}, _from, state) do
    file = Path.join(state.profiles_dir, "#{id}.json")

    case File.rm(file) do
      :ok ->
        new_active = if state.active && state.active.id == id, do: nil, else: state.active
        {:reply, :ok, %{state | active: new_active}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:switch, id, opts}, _from, state) do
    on_progress = Keyword.get(opts, :on_progress, fn _ -> :ok end)

    case find_profile(id, state.profiles_dir) do
      nil ->
        {:reply, {:error, :profile_not_found}, state}

      profile ->
        on_progress.("Switching to #{profile.name}...")

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

  defp rageg_base_dir do
    profiles_dir() |> Path.dirname()
  end

  defp load_all_profiles(dir) do
    dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.flat_map(fn file ->
      case File.read(file) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, map} -> [Profile.from_json(map)]
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

    case Jason.encode(profile, pretty: true) do
      {:ok, json} -> File.write(file, json)
      error -> error
    end
  end

  defp dllb_connected? do
    Application.get_env(:dllb, :enabled, false) &&
      match?({:ok, _}, Dllb.query("SELECT 1"))
  rescue
    _ -> false
  end
end
