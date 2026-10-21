defmodule Rageg.Embeddings do
  @moduledoc """
  Context module for the Embedding Space visualization.

  Wraps `Ragex.Graph.Store` and `Ragex.VectorStore` to provide:

  - 2D projections of high-dimensional code embeddings (via PCA)
  - Semantic search with result highlighting
  - k-NN neighbor discovery
  - Embedding metadata for coloring/filtering

  ## 2D Projection

  Uses PCA (Principal Component Analysis) to reduce high-dimensional
  embeddings to 2D for scatter plot rendering. This runs server-side and
  returns `{x, y}` coordinates for each entity.

  The projection is computed with `Nx` (SVD of the mean-centred data matrix),
  so it runs on the configured EXLA backend and gives the mathematically
  correct principal components -- including sign-stable, unit-variance axes.
  """

  alias Ragex.Graph.Store
  alias Ragex.Retrieval.Hybrid
  alias Ragex.Store.Backend
  alias Ragex.VectorStore

  @default_max_points 500

  @type point :: %{
          id: String.t(),
          x: float(),
          y: float(),
          type: String.t(),
          label: String.t(),
          module_name: String.t() | nil,
          community: term()
        }

  @doc """
  Fetches all embeddings as 2D-projected scatter points.

  Returns `{:ok, [point]}` with x/y coordinates computed via PCA.

  ## Options

    * `:max_points` - max entities to include (default: 500)
    * `:node_type` - filter by type (:function, :module, etc.)
  """
  @spec fetch_scatter_data(keyword()) :: {:ok, [point()]}
  def fetch_scatter_data(opts \\ []) do
    max_points = Keyword.get(opts, :max_points, @default_max_points)
    node_type = Keyword.get(opts, :node_type)

    embeddings = list_embeddings(node_type, max_points)

    if embeddings == [] do
      {:ok, []}
    else
      # Extract vectors and metadata
      vectors = Enum.map(embeddings, fn {_type, _id, emb, _text} -> emb end)
      projected = project_2d(vectors)

      points =
        embeddings
        |> Enum.zip(projected)
        |> Enum.map(fn {{type, id, _emb, text}, {x, y}} ->
          %{
            id: format_id(type, id),
            x: x,
            y: y,
            type: to_string(type),
            label: short_label(type, id, text),
            module_name: extract_module(type, id),
            community: nil
          }
        end)

      {:ok, points}
    end
  rescue
    e -> Rageg.Diagnostics.suppressed(:embeddings_scatter, e, {:ok, []})
  end

  @doc """
  Performs semantic search and returns matching entity IDs.

  Used to highlight search results in the scatter plot.
  """
  @spec search(String.t(), keyword()) :: {:ok, [String.t()]}
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    case Hybrid.search(query, limit: limit, strategy: :semantic_first) do
      {:ok, results} ->
        ids =
          results
          |> Enum.map(fn result ->
            format_id(result.node_type, result.node_id)
          end)

        {:ok, ids}

      _ ->
        {:ok, []}
    end
  rescue
    e -> Rageg.Diagnostics.suppressed(:embeddings_search, e, {:ok, []})
  end

  @doc """
  Finds k nearest neighbors for a given entity.

  Returns the IDs of the k closest entities by cosine similarity.
  """
  @spec nearest_neighbors(String.t(), non_neg_integer()) :: {:ok, [String.t()]}
  def nearest_neighbors(entity_id, k \\ 5) do
    embeddings = list_embeddings(nil, @default_max_points)

    case Enum.find(embeddings, fn {type, id, _emb, _text} -> format_id(type, id) == entity_id end) do
      {_type, _id, source_embedding, _text} when is_list(source_embedding) ->
        if dllb_backend?() do
          case VectorStore.search(source_embedding, limit: k + 1) do
            results when is_list(results) ->
              ids =
                results
                |> Enum.map(fn r -> format_id(r.node_type, r.node_id) end)
                |> Enum.reject(fn id -> id == entity_id end)
                |> Enum.take(k)

              {:ok, ids}

            _ ->
              {:ok, []}
          end
        else
          ids =
            embeddings
            |> Enum.map(fn {type, id, embedding, _text} ->
              {format_id(type, id), VectorStore.cosine_similarity(source_embedding, embedding)}
            end)
            |> Enum.reject(fn {id, _score} -> id == entity_id end)
            |> Enum.sort_by(fn {_id, score} -> score end, :desc)
            |> Enum.take(k)
            |> Enum.map(fn {id, _score} -> id end)

          {:ok, ids}
        end

      _ ->
        {:ok, []}
    end
  rescue
    e -> Rageg.Diagnostics.suppressed(:embeddings_neighbors, e, {:ok, []})
  end

  @doc "Returns embedding space statistics."
  @spec stats() :: map()
  def stats do
    vs =
      case VectorStore.stats() do
        s when is_map(s) -> s
        _ -> %{}
      end

    %{
      total: Map.get(vs, :total_embeddings, 0),
      dimensions: resolve_dimensions(Map.get(vs, :dimensions, 0))
    }
  rescue
    e -> Rageg.Diagnostics.suppressed(:embeddings_stats, e, %{total: 0, dimensions: 0})
  end

  # Selects the embedding source for the active store backend. Since both the
  # ETS and Dllb store backends now natively implement list_embeddings/2, we
  # delegate directly to the active backend.
  defp list_embeddings(node_type, limit) do
    Store.list_embeddings(node_type, limit)
  end

  defp dllb_backend? do
    Backend.module() == Backend.Dllb
  rescue
    _ -> false
  end

  # VectorStore.stats/0 derives dimensions from a sample embedding, which the
  # dllb backend does not list (so it reports 0). Fall back to the configured
  # model's dimension from the registry in that case.
  defp resolve_dimensions(dim) when is_integer(dim) and dim > 0, do: dim

  defp resolve_dimensions(_) do
    model_id = Application.get_env(:ragex, :embedding_model, Ragex.Embeddings.Registry.default())

    case Ragex.Embeddings.Registry.dimensions(model_id) do
      {:ok, dim} -> dim
      _ -> 0
    end
  rescue
    _ -> 0
  end

  # -- Private: 2D projection via PCA --

  @doc false
  # Projects a list of equal-length vectors onto their first two principal
  # components. Exposed (as `@doc false`) so the projection can be tested
  # directly without an embedding store.
  @spec project_2d([[number()]]) :: [{float(), float()}]
  def project_2d(vectors) when length(vectors) < 2 do
    Enum.map(vectors, fn _ -> {0.0, 0.0} end)
  end

  def project_2d(vectors) do
    dim = length(hd(vectors))

    case Nx.tensor(vectors, type: :f32) do
      %Nx.Tensor{shape: {n, ^dim}} = tensor when n >= 2 and dim >= 2 ->
        projected =
          tensor
          |> Nx.subtract(Nx.mean(tensor, axes: [0]))
          |> pca_components()

        projected
        |> Nx.to_flat_list()
        |> Enum.chunk_every(2)
        |> Enum.map(fn [x, y] -> {x, y} end)

      _ ->
        # Degenerate input (single dimension, ragged rows): fall back to a flat
        # line so the scatter plot still renders something sensible.
        Enum.with_index(vectors, fn _v, idx -> {idx * 1.0, 0.0} end)
    end
  rescue
    e ->
      Rageg.Diagnostics.suppressed(:embeddings_project_2d, e) ||
        Enum.map(vectors, fn _ -> {0.0, 0.0} end)
  end

  # Projects centred data onto its first two right singular vectors.
  #
  # For an n x d centred matrix X, the principal axes are the columns of V
  # from X = U S V^T, and the coordinates are X V. `Nx.LinAlg.svd/2` returns
  # {u, s, v} with v of shape {d, d}; we keep the first two columns.
  defp pca_components(centred) do
    {_u, _s, v} = Nx.LinAlg.svd(centred)
    Nx.dot(centred, v[[.., 0..1]])
  end

  # -- Private: formatting --

  defp format_id(:function, {mod, name, arity}), do: "#{mod}.#{name}/#{arity}"
  defp format_id(:module, name), do: "#{name}"
  defp format_id(type, id), do: "#{type}:#{inspect(id)}"

  defp short_label(:function, {_mod, name, arity}, _text), do: "#{name}/#{arity}"

  defp short_label(:module, name, _text),
    do: name |> to_string() |> String.split(".") |> List.last()

  defp short_label(_, _, text) when is_binary(text), do: String.slice(text, 0, 30)
  defp short_label(_, id, _), do: inspect(id)

  defp extract_module(:function, {mod, _, _}), do: to_string(mod)
  defp extract_module(:module, name), do: to_string(name)
  defp extract_module(_, _), do: nil
end
