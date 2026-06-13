defmodule Rageg.Embeddings do
  @moduledoc """
  Context module for the Embedding Space visualization.

  Wraps `Ragex.Graph.Store` and `Ragex.VectorStore` to provide:

  - 2D projections of high-dimensional code embeddings (via PCA)
  - Semantic search with result highlighting
  - k-NN neighbor discovery
  - Embedding metadata for coloring/filtering

  ## 2D Projection

  Uses a simplified PCA (Principal Component Analysis) to reduce
  384-dimensional embeddings to 2D for scatter plot rendering. This
  runs server-side and returns `{x, y}` coordinates for each entity.
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
    _ -> {:ok, []}
  end

  @doc """
  Performs semantic search and returns matching entity IDs.

  Used to highlight search results in the scatter plot.
  """
  @spec search(String.t(), keyword()) :: {:ok, [String.t()]}
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    if dllb_backend?() do
      dllb_search(query, limit)
    else
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
    end
  rescue
    _ -> {:ok, []}
  end

  # On the dllb backend the native vector search returns only kind/name (no
  # module or arity), so its IDs would not match the scatter point IDs. Rank
  # the sampled embedding set against the query embedding instead, producing
  # the same `Module.fun/arity` IDs the plot uses so highlighting lines up.
  defp dllb_search(query, limit) do
    with {:ok, query_embedding} <- Ragex.Embeddings.Bumblebee.embed(query) do
      ids =
        nil
        |> list_embeddings(@default_max_points)
        |> Enum.map(fn {type, id, embedding, _text} ->
          {format_id(type, id), VectorStore.cosine_similarity(query_embedding, embedding)}
        end)
        |> Enum.sort_by(fn {_id, score} -> score end, :desc)
        |> Enum.take(limit)
        |> Enum.map(fn {id, _score} -> id end)

      {:ok, ids}
    else
      _ -> {:ok, []}
    end
  end

  @doc """
  Finds k nearest neighbors for a given entity.

  Returns the IDs of the k closest entities by cosine similarity.
  """
  @spec nearest_neighbors(String.t(), non_neg_integer()) :: {:ok, [String.t()]}
  def nearest_neighbors(entity_id, k \\ 5) do
    # Rank neighbors by cosine similarity within the sampled embedding set.
    # This works identically for the ETS and dllb backends and, crucially,
    # yields IDs in the same `Module.fun/arity` shape as the scatter points so
    # the client can draw connector lines to the displayed neighbors.
    embeddings = list_embeddings(nil, @default_max_points)

    case Enum.find(embeddings, fn {type, id, _emb, _text} -> format_id(type, id) == entity_id end) do
      {_type, _id, source_embedding, _text} ->
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

      nil ->
        {:ok, []}
    end
  rescue
    _ -> {:ok, []}
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
    _ -> %{total: 0, dimensions: 0}
  end

  # Selects the embedding source for the active store backend. The dllb store
  # backend does not list embeddings (it returns []), so pull a capped sample
  # straight from dllb; otherwise use the in-memory ETS store.
  defp list_embeddings(node_type, limit) do
    if dllb_backend?() do
      Rageg.Dllb.list_embeddings(node_type, limit)
    else
      Store.list_embeddings(node_type, limit)
    end
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

  defp project_2d(vectors) when length(vectors) < 2 do
    Enum.map(vectors, fn _ -> {0.0, 0.0} end)
  end

  defp project_2d(vectors) do
    # Simple PCA: compute mean, subtract, find top-2 principal directions
    dim = length(hd(vectors))
    n = length(vectors)

    # Mean vector
    mean = mean_vector(vectors, dim, n)

    # Center the data
    centered = Enum.map(vectors, fn v -> subtract_vectors(v, mean) end)

    # Compute covariance approximation using random projection
    # (full covariance is O(d^2) which is fine for d=384)
    # For simplicity, use the first two left singular vectors via power iteration
    pc1 = power_iteration(centered, dim)
    pc2 = power_iteration_deflated(centered, dim, pc1)

    # Project each vector onto the two principal components
    Enum.map(centered, fn v ->
      x = dot(v, pc1)
      y = dot(v, pc2)
      {x, y}
    end)
  end

  defp mean_vector(vectors, dim, n) do
    sum =
      Enum.reduce(vectors, List.duplicate(0.0, dim), fn v, acc ->
        Enum.zip(acc, v) |> Enum.map(fn {a, b} -> a + b end)
      end)

    Enum.map(sum, &(&1 / n))
  end

  defp subtract_vectors(a, b) do
    Enum.zip(a, b) |> Enum.map(fn {x, y} -> x - y end)
  end

  defp dot(a, b) do
    Enum.zip(a, b) |> Enum.map(fn {x, y} -> x * y end) |> Enum.sum()
  end

  defp normalize(v) do
    mag = :math.sqrt(dot(v, v))
    if mag == 0.0, do: v, else: Enum.map(v, &(&1 / mag))
  end

  # Power iteration to find top eigenvector of X^T X
  defp power_iteration(centered, dim) do
    # Random initial vector
    :rand.seed(:exsplus, {42, 42, 42})
    initial = Enum.map(1..dim, fn _ -> :rand.normal() end) |> normalize()

    Enum.reduce(1..20, initial, fn _i, v ->
      # Multiply by X^T X: first X*v, then X^T * (X*v)
      xv = Enum.map(centered, fn row -> dot(row, v) end)

      xtxv =
        Enum.reduce(Enum.zip(centered, xv), List.duplicate(0.0, dim), fn {row, coeff}, acc ->
          Enum.zip(acc, row) |> Enum.map(fn {a, r} -> a + r * coeff end)
        end)

      normalize(xtxv)
    end)
  end

  # Find second principal component by deflating the first
  defp power_iteration_deflated(centered, dim, pc1) do
    # Deflate: remove projection onto pc1
    deflated =
      Enum.map(centered, fn v ->
        proj = dot(v, pc1)
        Enum.zip(v, pc1) |> Enum.map(fn {vi, pi} -> vi - proj * pi end)
      end)

    power_iteration(deflated, dim)
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
