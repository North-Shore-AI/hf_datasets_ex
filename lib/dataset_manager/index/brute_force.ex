defmodule HfDatasetsEx.Index.BruteForce do
  @moduledoc """
  Pure Elixir brute-force similarity search.

  Slower than specialized libraries but works everywhere.

  ## Examples

      index = BruteForce.new("embeddings", metric: :cosine)
      index = BruteForce.add(index, embeddings_tensor)

      results = BruteForce.search(index, query_vector, k: 10)
      # [{0.95, 42}, {0.93, 17}, ...]

  """

  @behaviour HfDatasetsEx.Index

  @type t :: %__MODULE__{
          column: String.t(),
          vectors: Nx.Tensor.t() | nil,
          metric: :l2 | :cosine | :inner_product,
          normalized: boolean()
        }

  defstruct [:column, :vectors, metric: :cosine, normalized: false]

  @impl true
  @spec new(String.t(), keyword()) :: t()
  def new(column, opts \\ []) do
    %__MODULE__{
      column: column,
      vectors: nil,
      metric: Keyword.get(opts, :metric, :cosine),
      normalized: false
    }
  end

  @impl true
  @spec add(t(), Nx.Tensor.t()) :: t()
  def add(%__MODULE__{vectors: nil} = index, vectors) do
    vectors = maybe_normalize(vectors, index.metric)
    %{index | vectors: vectors, normalized: index.metric == :cosine}
  end

  def add(%__MODULE__{vectors: existing} = index, vectors) do
    vectors = maybe_normalize(vectors, index.metric)
    combined = Nx.concatenate([existing, vectors], axis: 0)
    %{index | vectors: combined}
  end

  @impl true
  @spec search(t(), Nx.Tensor.t(), non_neg_integer()) :: [{float(), non_neg_integer()}]
  def search(%__MODULE__{vectors: nil}, _query, _k), do: []

  def search(%__MODULE__{vectors: vectors, metric: metric} = index, query, k) do
    query = maybe_normalize(Nx.reshape(query, {Nx.axis_size(query, -1)}), metric)

    scores = compute_scores(vectors, query, metric, index.normalized)

    {top_scores, top_indices} = top_k(scores, k)

    Enum.zip(
      Nx.to_flat_list(top_scores),
      Nx.to_flat_list(top_indices)
    )
  end

  @impl true
  @spec save(t(), Path.t()) :: :ok | {:error, term()}
  def save(%__MODULE__{} = index, path) do
    data = %{
      column: index.column,
      metric: index.metric,
      vectors: if(index.vectors, do: Nx.to_binary(index.vectors)),
      shape: if(index.vectors, do: Nx.shape(index.vectors)),
      type: if(index.vectors, do: Nx.type(index.vectors))
    }

    File.write(path, :erlang.term_to_binary(data))
  end

  @impl true
  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path) do
    data = path |> File.read!() |> :erlang.binary_to_term()

    vectors =
      if data.vectors do
        data.vectors
        |> Nx.from_binary(data.type)
        |> Nx.reshape(data.shape)
      end

    index = %__MODULE__{
      column: data.column,
      metric: data.metric,
      vectors: vectors,
      normalized: data.metric == :cosine
    }

    {:ok, index}
  rescue
    e -> {:error, e}
  end

  defp maybe_normalize(tensor, :cosine) do
    norms = Nx.sqrt(Nx.sum(Nx.multiply(tensor, tensor), axes: [-1], keep_axes: true))
    Nx.divide(tensor, Nx.max(norms, 1.0e-10))
  end

  defp maybe_normalize(tensor, _metric), do: tensor

  defp compute_scores(vectors, query, :cosine, true) do
    Nx.dot(vectors, query)
  end

  defp compute_scores(vectors, query, :cosine, false) do
    vectors = maybe_normalize(vectors, :cosine)
    query = maybe_normalize(query, :cosine)
    Nx.dot(vectors, query)
  end

  defp compute_scores(vectors, query, :inner_product, _normalized) do
    Nx.dot(vectors, query)
  end

  defp compute_scores(vectors, query, :l2, _normalized) do
    diff = Nx.subtract(vectors, query)
    distances = Nx.sum(Nx.multiply(diff, diff), axes: [-1])
    Nx.negate(distances)
  end

  defp top_k(scores, k) do
    n = Nx.axis_size(scores, 0)
    k = min(k, n)

    indices = Nx.argsort(scores, direction: :desc)
    top_indices = Nx.slice(indices, [0], [k])

    top_scores = Nx.take(scores, top_indices)

    {top_scores, top_indices}
  end
end
