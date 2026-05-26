defmodule Rageg.Profile do
  @moduledoc """
  A project profile -- metadata pointing to a directory with ingested code.

  Profiles are persisted as JSON files in the profiles directory
  (`~/.rageg/profiles/` by default). Each profile tracks:

  - The absolute path to the project directory
  - A display name (defaults to the directory basename)
  - A `dllb_project_tag` used to scope dllb queries with `WHERE project_path = ...`
  - Timestamps for creation and last ingestion
  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          path: String.t(),
          dllb_project_tag: String.t(),
          created_at: String.t(),
          last_ingested_at: String.t() | nil
        }

  defstruct [:id, :name, :path, :dllb_project_tag, :created_at, :last_ingested_at]

  @doc "Creates a new profile from a directory path and optional name."
  @spec new(String.t(), String.t() | nil) :: t()
  def new(path, name \\ nil) do
    abs_path = Path.expand(path)
    base_name = name || Path.basename(abs_path)
    tag = base_name |> String.downcase() |> String.replace(~r/[^a-z0-9_]/, "_")

    %__MODULE__{
      id: generate_id(),
      name: base_name,
      path: abs_path,
      dllb_project_tag: tag,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      last_ingested_at: nil
    }
  end

  @doc "Deserializes a profile from a decoded JSON map."
  @spec from_json(map()) :: t()
  def from_json(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      name: map["name"],
      path: map["path"],
      dllb_project_tag: map["dllb_project_tag"],
      created_at: map["created_at"],
      last_ingested_at: map["last_ingested_at"]
    }
  end

  @doc "Marks the profile as freshly ingested."
  @spec mark_ingested(t()) :: t()
  def mark_ingested(%__MODULE__{} = profile) do
    %{profile | last_ingested_at: DateTime.utc_now() |> DateTime.to_iso8601()}
  end

  defp generate_id do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
  end
end
