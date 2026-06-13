defmodule Rageg.Dllb do
  @moduledoc """
  Context module for the dllb Backend Explorer.

  Wraps the `Dllb` client to provide health checks, schema introspection,
  query execution, and MetaAST node type information for the DllbLive
  sub-pages.

  All functions handle the case where dllb is not connected gracefully.
  """

  @stats_file "~/.rageg/.dllb_stats.json"

  # SurrealDB-style RELATE edge tables that must be wiped on full reset.
  @edge_tables ~w[calls contains imports type_ref inherits defines]

  # Default cap on how many embedding rows to sample from dllb at once. The
  # backend deliberately never streams every vector, so callers take a sample.
  @embedding_sample_limit 1_000

  @doc "Returns true if dllb pool is enabled and reachable."
  @spec connected?() :: boolean()
  def connected? do
    Application.get_env(:dllb, :enabled, false) &&
      match?({:ok, %Dllb.Result.Rows{}}, Dllb.query("SELECT * FROM _dllb_ping_"))
  rescue
    _ -> false
  end

  @doc """
  Persists ingestion stats to `~/.rageg/.dllb_stats.json`.

  Merges the given project stats into the existing file so that
  core and project ingestion counts accumulate.
  """
  @spec save_ingest_stats(String.t(), map()) :: :ok | {:error, term()}
  def save_ingest_stats(project_tag, stats) when is_map(stats) do
    path = Path.expand(@stats_file)
    existing = load_ingest_stats()

    entry = %{
      "files" => Map.get(stats, :files_ok, 0),
      "nodes" => Map.get(stats, :nodes, 0),
      "edges" => Map.get(stats, :edges, 0),
      "ingested_at" => DateTime.to_iso8601(DateTime.utc_now())
    }

    merged = Map.put(existing, project_tag, entry)

    File.mkdir_p!(Path.dirname(path))
    File.write(path, IO.iodata_to_binary(:json.encode(merged)))
  end

  @doc "Loads persisted ingestion stats from disk."
  @spec load_ingest_stats() :: map()
  def load_ingest_stats do
    path = Path.expand(@stats_file)

    case File.read(path) do
      {:ok, json} -> :json.decode(json)
      _ -> %{}
    end
  rescue
    _ -> %{}
  end

  @doc "Returns aggregate node/edge totals across all ingested projects."
  @spec aggregate_ingest_stats() :: %{
          nodes: non_neg_integer(),
          edges: non_neg_integer(),
          projects: non_neg_integer()
        }
  def aggregate_ingest_stats do
    stats = load_ingest_stats()

    Enum.reduce(stats, %{nodes: 0, edges: 0, projects: 0}, fn {_tag, entry}, acc ->
      %{
        nodes: acc.nodes + Map.get(entry, "nodes", 0),
        edges: acc.edges + Map.get(entry, "edges", 0),
        projects: acc.projects + 1
      }
    end)
  end

  @doc """
  Full state reset: wipes dllb, stats cache, ingest cache, and all profiles.

  Clears the following in order:

    1. `~/.rageg/.dllb_stats.json` -- persisted dashboard node/edge counts
    2. Per-file ingest-cache manifests -- so every file is treated as new on
       the next ingestion run
    3. All project profiles -- JSON files in `~/.rageg/profiles/` and the
       GenServer's active-profile state; broadcasts `{:profile_switched, nil}`
    4. dllb tables -- `ast_node`, `_edge_idx`, and all RELATE edge tables

  Raises on file system errors. dllb query failures are logged but do not
  raise since the server may not be running.
  """
  @spec clear_all!() :: :ok
  def clear_all! do
    # 1. Wipe the persisted stats JSON.
    stats_path = Path.expand(@stats_file)

    if File.exists?(stats_path) do
      File.rm!(stats_path)
    end

    # 2. Clear per-file ingest-cache manifests.
    Rageg.Profiles.IngestCache.clear_all!()

    # 3. Delete all saved project profiles and clear the active state.
    Rageg.Profiles.clear_all!()

    # 4. Clear dllb tables if the server is reachable.
    tables = ["ast_node", "_edge_idx" | @edge_tables]

    Enum.each(tables, fn table ->
      case Dllb.query("DELETE #{table}") do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          require(Logger)
          Logger.warning("[Rageg.Dllb.clear_all!] DELETE #{table} failed: #{inspect(reason)}")
      end
    end)

    :ok
  end

  @doc "Returns dllb connection configuration."
  @spec config() :: map()
  def config do
    %{
      host: Application.get_env(:dllb, :host, "127.0.0.1"),
      port: Application.get_env(:dllb, :port, 3009),
      pool_size: Application.get_env(:dllb, :pool_size, 5),
      enabled: Application.get_env(:dllb, :enabled, false)
    }
  end

  @doc """
  Executes a raw query against the dllb server.

  Returns `{:ok, result}` or `{:error, reason}`.
  """
  @spec query(String.t()) :: {:ok, term()} | {:error, term()}
  def query(query_string) do
    Dllb.query(query_string)
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Returns a capped sample of stored embeddings straight from dllb.

  The dllb store backend in Ragex deliberately does not list embeddings
  (`Ragex.Graph.Store.list_embeddings/2` returns `[]` under it) to avoid
  streaming every vector over the wire. This selects `ast_node` rows that
  carry a `source_embedding` and normalizes them into the same
  `{node_type, node_id, embedding, text}` tuples the ETS backend produces, so
  callers (e.g. the Embedding Space view) can treat both backends uniformly.

  `node_type` is `:function` or `:module`; `node_id` is `{module, name, arity}`
  for functions and the module name for modules, matching the
  `Module.fun/arity` identifiers used elsewhere in the UI. An optional
  `node_type` filter (`:function` or `:module`) scopes the sample server-side.

  Returns `[]` if dllb is unreachable or the query fails.
  """
  @spec list_embeddings(:function | :module | nil, pos_integer()) ::
          [{:function | :module, term(), [float()], String.t()}]
  def list_embeddings(node_type \\ nil, limit \\ @embedding_sample_limit) do
    query_string =
      Dllb.Query.select("ast_node",
        fields: ~w[id kind name module arity source_text source_embedding],
        where: embedding_where(node_type),
        limit: limit
      )

    case Dllb.query(query_string) do
      {:ok, %Dllb.Result.Rows{data: rows}} ->
        rows
        |> Enum.map(&row_to_embedding/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  @doc """
  Returns the schema definition statements for the ast_node table.

  Useful for displaying the schema structure in the storage sub-page.
  """
  @spec schema_statements() :: [String.t()]
  def schema_statements do
    Dllb.Schema.all_statements()
  rescue
    _ -> []
  end

  @doc """
  Returns the schema fields for the ast_node table.

  Returns a list of `{name, type, required?}` tuples.
  """
  @spec schema_fields() :: [{String.t(), String.t(), boolean()}]
  def schema_fields do
    [
      {"kind", "string", true},
      {"name", "string", false},
      {"language", "string", true},
      {"file_path", "string", true},
      {"module", "string", false},
      {"arity", "int", false},
      {"visibility", "string", false},
      {"project_path", "string", false},
      {"line_start", "int", false},
      {"line_end", "int", false},
      {"source_text", "string", false},
      {"signature", "string", false},
      {"docstring", "string", false},
      {"source_embedding", "array (768d)", false},
      {"structure_embedding", "array (384d)", false}
    ]
  end

  @doc """
  Returns the index definitions for the ast_node table.

  Returns a list of `{name, fields, type}` tuples.
  """
  @spec schema_indexes() :: [{String.t(), [String.t()], String.t()}]
  def schema_indexes do
    [
      {"idx_kind", ["kind"], "btree"},
      {"idx_language", ["language"], "btree"},
      {"idx_file_path", ["file_path"], "btree"},
      {"idx_module", ["module"], "btree"},
      {"idx_project_path", ["project_path"], "btree"},
      {"idx_file_kind", ["file_path", "kind"], "btree (composite)"},
      {"idx_source_embedding", ["source_embedding"], "HNSW 768d cosine"},
      {"idx_structure_embedding", ["structure_embedding"], "HNSW 384d cosine"},
      {"idx_source_text", ["source_text"], "fulltext"},
      {"idx_docstring", ["docstring"], "fulltext"}
    ]
  end

  @doc "Returns the 38 MetaAST node types supported by dllb code-intel."
  @spec meta_ast_node_types() :: [String.t()]
  def meta_ast_node_types do
    [
      "container",
      "function_def",
      "function_call",
      "variable",
      "assignment",
      "binary_op",
      "unary_op",
      "literal",
      "string_literal",
      "number_literal",
      "boolean_literal",
      "nil_literal",
      "list",
      "tuple",
      "map",
      "keyword",
      "if",
      "case",
      "cond",
      "with",
      "for",
      "while",
      "try",
      "rescue",
      "catch",
      "throw",
      "raise",
      "return",
      "import",
      "alias",
      "require",
      "use",
      "module_attribute",
      "type_def",
      "guard",
      "lambda",
      "pattern",
      "comment"
    ]
  end

  @doc """
  Returns the dllb actor supervision tree structure.

  This is a static representation based on dllb's architecture.
  """
  @spec supervision_tree() :: map()
  def supervision_tree do
    %{
      name: "dllb_sup",
      strategy: "OneForAll",
      children: [
        %{
          name: "storage_sup",
          strategy: "OneForOne",
          children: [
            %{
              name: "StorageWriter",
              type: "GenServer",
              status: if(connected?(), do: :alive, else: :unknown)
            }
          ]
        },
        %{
          name: "index_sup",
          strategy: "OneForOne",
          children: [
            %{
              name: "FtsActor",
              type: "GenServer",
              status: if(connected?(), do: :alive, else: :unknown)
            },
            %{
              name: "HnswActor",
              type: "GenServer",
              status: if(connected?(), do: :alive, else: :unknown)
            },
            %{
              name: "GcActor",
              type: "periodic",
              status: if(connected?(), do: :alive, else: :unknown)
            }
          ]
        },
        %{
          name: "client_sup",
          strategy: "OneForOne",
          children: [
            %{
              name: "ConnectionActor",
              type: "per-client",
              status: if(connected?(), do: :alive, else: :unknown)
            }
          ]
        }
      ]
    }
  end

  @doc "Edge types used by the dllb graph model for code intelligence."
  @spec edge_types() :: [{String.t(), String.t()}]
  def edge_types do
    [
      {"contains", "Container -> child node relationships"},
      {"calls", "Function call edges (caller -> callee)"},
      {"imports", "Import/require/use dependencies"},
      {"type_ref", "Type references between nodes"},
      {"inherits", "Inheritance/implementation relationships"},
      {"defines", "Module -> function definition edges"}
    ]
  end

  # -- Private: embedding sampling --

  # Restricts the sample to rows that actually carry a vector, optionally
  # scoped to the kind backing a given node type.
  defp embedding_where(:function), do: "kind = 'function_def' AND source_embedding IS NOT NONE"
  defp embedding_where(:module), do: "kind = 'container' AND source_embedding IS NOT NONE"
  defp embedding_where(_), do: "source_embedding IS NOT NONE"

  # Normalizes a raw dllb row into the ETS-compatible embedding tuple, or nil
  # for rows without a usable vector or a recognized kind.
  defp row_to_embedding(row) do
    embedding = unwrap_vector(row["source_embedding"])

    case {unwrap(row["kind"]), embedding} do
      {_kind, []} ->
        nil

      {"function_def", emb} ->
        node_id = {unwrap(row["module"]), unwrap(row["name"]), unwrap(row["arity"])}
        {:function, node_id, emb, unwrap(row["source_text"]) || ""}

      {"container", emb} ->
        {:module, unwrap(row["name"]), emb, unwrap(row["source_text"]) || ""}

      _ ->
        nil
    end
  end

  # dllb serde-tags scalar values by variant: %{"String" => v}, %{"Int" => n}, ...
  # `Value::None` serializes to the bare string "None".
  defp unwrap(%{"String" => v}), do: v
  defp unwrap(%{"Int" => v}), do: v
  defp unwrap(%{"Float" => v}), do: v
  defp unwrap(%{"Bool" => v}), do: v
  defp unwrap("None"), do: nil
  defp unwrap(v), do: v

  # Vectors arrive as %{"Array" => [%{"Float" => f}, ...]} (or a bare list).
  # Returns a plain list of floats, or [] for anything else.
  defp unwrap_vector(%{"Array" => list}) when is_list(list), do: Enum.map(list, &unwrap_float/1)
  defp unwrap_vector(list) when is_list(list), do: Enum.map(list, &unwrap_float/1)
  defp unwrap_vector(_), do: []

  defp unwrap_float(%{"Float" => v}) when is_number(v), do: v * 1.0
  defp unwrap_float(%{"Int" => v}) when is_number(v), do: v * 1.0
  defp unwrap_float(v) when is_number(v), do: v * 1.0
  defp unwrap_float(_), do: 0.0
end
