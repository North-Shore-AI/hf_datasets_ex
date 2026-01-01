# Implementation Prompt: Search and Indexing

## Priority: P3 (Low)

## Objective

Implement vector similarity search and full-text search capabilities for datasets.

## Required Reading

Before starting, read these files completely:

```
lib/dataset_manager/dataset.ex
mix.exs
docs/20251231/gap_analysis/08_search_indexing.md
```

## Context

The Python `datasets` library supports:
- FAISS integration for vector similarity search
- Elasticsearch integration for full-text search

These features enable:
- Semantic search over embeddings
- Fast nearest neighbor lookup
- Full-text search in large datasets

Given P3 priority, we'll implement:
1. Pure Elixir brute-force search (works everywhere)
2. Optional Qdrant integration (easy REST API)

Skip FAISS NIF and Elasticsearch for now.

## Implementation Requirements

### 1. Index Behaviour

Create `lib/dataset_manager/index.ex`:

```elixir
defmodule HfDatasetsEx.Index do
  @moduledoc """
  Behaviour for search indices.
  """

  @type t :: struct()
  @type search_result :: {float(), non_neg_integer()}  # {score, index}

  @callback new(String.t(), keyword()) :: t()
  @callback add(t(), Nx.Tensor.t()) :: t()
  @callback search(t(), Nx.Tensor.t(), non_neg_integer()) :: [search_result()]
  @callback save(t(), Path.t()) :: :ok | {:error, term()}
  @callback load(Path.t()) :: {:ok, t()} | {:error, term()}

  @optional_callbacks [save: 2, load: 1]
end
```

### 2. Brute Force Index

Create `lib/dataset_manager/index/brute_force.ex`:

```elixir
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

    # Get top k indices
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
    try do
      data = path |> File.read!() |> :erlang.binary_to_term()

      vectors = if data.vectors do
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
  end

  # Private functions

  defp maybe_normalize(tensor, :cosine) do
    norms = Nx.sqrt(Nx.sum(Nx.multiply(tensor, tensor), axes: [-1], keep_axes: true))
    Nx.divide(tensor, Nx.max(norms, 1.0e-10))
  end

  defp maybe_normalize(tensor, _metric), do: tensor

  defp compute_scores(vectors, query, :cosine, true) do
    # Already normalized, just dot product
    Nx.dot(vectors, query)
  end

  defp compute_scores(vectors, query, :cosine, false) do
    # Normalize on the fly
    vectors = maybe_normalize(vectors, :cosine)
    query = maybe_normalize(query, :cosine)
    Nx.dot(vectors, query)
  end

  defp compute_scores(vectors, query, :inner_product, _normalized) do
    Nx.dot(vectors, query)
  end

  defp compute_scores(vectors, query, :l2, _normalized) do
    # L2 distance - negate so higher is better (like similarity)
    diff = Nx.subtract(vectors, query)
    distances = Nx.sum(Nx.multiply(diff, diff), axes: [-1])
    Nx.negate(distances)
  end

  defp top_k(scores, k) do
    n = Nx.axis_size(scores, 0)
    k = min(k, n)

    # Argsort descending
    indices = Nx.argsort(scores, direction: :desc)
    top_indices = Nx.slice(indices, [0], [k])

    top_scores = Nx.take(scores, top_indices)

    {top_scores, top_indices}
  end
end
```

### 3. Dataset Integration

Add to `lib/dataset_manager/dataset.ex`:

```elixir
defmodule HfDatasetsEx.Dataset do
  alias HfDatasetsEx.Index.BruteForce

  @doc """
  Add a search index for a column.

  ## Options

    * `:metric` - Distance metric: :cosine, :l2, :inner_product (default: :cosine)
    * `:index_type` - Index implementation (default: :brute_force)

  ## Examples

      dataset = Dataset.add_index(dataset, "embeddings", metric: :cosine)

  """
  @spec add_index(t(), String.t(), keyword()) :: t()
  def add_index(%__MODULE__{} = dataset, column, opts \\ []) do
    metric = Keyword.get(opts, :metric, :cosine)
    index_type = Keyword.get(opts, :index_type, :brute_force)

    # Extract vectors from column
    vectors =
      dataset.items
      |> Enum.map(&Map.get(&1, column))
      |> Nx.stack()

    # Create index
    index = case index_type do
      :brute_force ->
        BruteForce.new(column, metric: metric)
        |> BruteForce.add(vectors)
    end

    # Store in metadata
    indices = Map.get(dataset.metadata, :indices, %{})
    metadata = Map.put(dataset.metadata, :indices, Map.put(indices, column, index))

    %{dataset | metadata: metadata}
  end

  @doc """
  Search for nearest examples to a query vector.

  ## Examples

      {scores, examples} = Dataset.get_nearest_examples(dataset, "embeddings", query, k: 10)

  """
  @spec get_nearest_examples(t(), String.t(), Nx.Tensor.t(), keyword()) ::
    {[float()], [map()]}
  def get_nearest_examples(%__MODULE__{} = dataset, column, query, opts \\ []) do
    k = Keyword.get(opts, :k, 10)

    index = get_in(dataset.metadata, [:indices, column])

    unless index do
      raise ArgumentError, """
      No index found for column "#{column}".
      Call Dataset.add_index(dataset, "#{column}") first.
      """
    end

    results = BruteForce.search(index, query, k)

    scores = Enum.map(results, fn {score, _idx} -> score end)
    examples = Enum.map(results, fn {_score, idx} -> Enum.at(dataset.items, idx) end)

    {scores, examples}
  end

  @doc """
  Save an index to a file.
  """
  @spec save_index(t(), String.t(), Path.t()) :: :ok | {:error, term()}
  def save_index(%__MODULE__{} = dataset, column, path) do
    index = get_in(dataset.metadata, [:indices, column])

    unless index do
      {:error, {:no_index, column}}
    else
      BruteForce.save(index, path)
    end
  end

  @doc """
  Load an index from a file.
  """
  @spec load_index(t(), String.t(), Path.t()) :: {:ok, t()} | {:error, term()}
  def load_index(%__MODULE__{} = dataset, column, path) do
    case BruteForce.load(path) do
      {:ok, index} ->
        index = %{index | column: column}
        indices = Map.get(dataset.metadata, :indices, %{})
        metadata = Map.put(dataset.metadata, :indices, Map.put(indices, column, index))
        {:ok, %{dataset | metadata: metadata}}

      error ->
        error
    end
  end

  @doc """
  Remove an index.
  """
  @spec drop_index(t(), String.t()) :: t()
  def drop_index(%__MODULE__{} = dataset, column) do
    indices = Map.get(dataset.metadata, :indices, %{})
    metadata = Map.put(dataset.metadata, :indices, Map.delete(indices, column))
    %{dataset | metadata: metadata}
  end
end
```

## TDD Approach

### Step 1: Write Tests First

Create `test/dataset_manager/index/brute_force_test.exs`:

```elixir
defmodule HfDatasetsEx.Index.BruteForceTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Index.BruteForce

  describe "new/2" do
    test "creates index with default options" do
      index = BruteForce.new("embeddings")

      assert index.column == "embeddings"
      assert index.metric == :cosine
      assert index.vectors == nil
    end

    test "respects metric option" do
      index = BruteForce.new("embeddings", metric: :l2)

      assert index.metric == :l2
    end
  end

  describe "add/2" do
    test "adds vectors to empty index" do
      index = BruteForce.new("embeddings")
      vectors = Nx.tensor([[1.0, 0.0], [0.0, 1.0]])

      index = BruteForce.add(index, vectors)

      assert index.vectors != nil
      assert Nx.shape(index.vectors) == {2, 2}
    end

    test "appends vectors to existing index" do
      index = BruteForce.new("embeddings")
      v1 = Nx.tensor([[1.0, 0.0]])
      v2 = Nx.tensor([[0.0, 1.0]])

      index = index |> BruteForce.add(v1) |> BruteForce.add(v2)

      assert Nx.shape(index.vectors) == {2, 2}
    end
  end

  describe "search/3" do
    test "returns empty for empty index" do
      index = BruteForce.new("embeddings")
      query = Nx.tensor([1.0, 0.0])

      assert BruteForce.search(index, query, 5) == []
    end

    test "finds nearest neighbors with cosine similarity" do
      vectors = Nx.tensor([
        [1.0, 0.0],  # idx 0: most similar to [1, 0]
        [0.0, 1.0],  # idx 1: orthogonal
        [0.707, 0.707]  # idx 2: 45 degrees
      ])

      index = BruteForce.new("embeddings", metric: :cosine)
              |> BruteForce.add(vectors)

      query = Nx.tensor([1.0, 0.0])
      results = BruteForce.search(index, query, 3)

      # Most similar should be first (idx 0)
      [{_score, first_idx} | _] = results
      assert first_idx == 0
    end

    test "finds nearest neighbors with L2 distance" do
      vectors = Nx.tensor([
        [0.0, 0.0],
        [1.0, 1.0],
        [10.0, 10.0]
      ])

      index = BruteForce.new("embeddings", metric: :l2)
              |> BruteForce.add(vectors)

      query = Nx.tensor([0.1, 0.1])
      results = BruteForce.search(index, query, 2)

      # Closest should be [0, 0] at idx 0
      [{_score, first_idx}, {_score2, second_idx}] = results
      assert first_idx == 0
      assert second_idx == 1
    end

    test "respects k limit" do
      vectors = Nx.tensor([
        [1.0, 0.0],
        [0.0, 1.0],
        [1.0, 1.0],
        [0.5, 0.5]
      ])

      index = BruteForce.new("embeddings")
              |> BruteForce.add(vectors)

      query = Nx.tensor([1.0, 0.0])
      results = BruteForce.search(index, query, 2)

      assert length(results) == 2
    end
  end

  describe "save/2 and load/1" do
    @temp_dir System.tmp_dir!()

    test "round-trip preserves index" do
      vectors = Nx.tensor([[1.0, 0.0], [0.0, 1.0]])

      index = BruteForce.new("embeddings", metric: :cosine)
              |> BruteForce.add(vectors)

      path = Path.join(@temp_dir, "test_index_#{:rand.uniform(100000)}.idx")

      assert :ok = BruteForce.save(index, path)
      assert {:ok, loaded} = BruteForce.load(path)

      assert loaded.column == index.column
      assert loaded.metric == index.metric
      assert Nx.shape(loaded.vectors) == Nx.shape(index.vectors)

      File.rm!(path)
    end
  end
end
```

Create `test/dataset_manager/dataset_search_test.exs`:

```elixir
defmodule HfDatasetsEx.DatasetSearchTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Dataset

  describe "add_index/3" do
    test "creates index from column" do
      dataset = Dataset.from_list([
        %{"id" => 1, "embedding" => [1.0, 0.0]},
        %{"id" => 2, "embedding" => [0.0, 1.0]},
        %{"id" => 3, "embedding" => [0.707, 0.707]}
      ])

      indexed = Dataset.add_index(dataset, "embedding")

      assert get_in(indexed.metadata, [:indices, "embedding"]) != nil
    end
  end

  describe "get_nearest_examples/4" do
    test "returns nearest examples" do
      dataset = Dataset.from_list([
        %{"id" => 1, "embedding" => [1.0, 0.0, 0.0]},
        %{"id" => 2, "embedding" => [0.0, 1.0, 0.0]},
        %{"id" => 3, "embedding" => [0.0, 0.0, 1.0]}
      ])

      indexed = Dataset.add_index(dataset, "embedding")

      query = Nx.tensor([1.0, 0.0, 0.0])
      {scores, examples} = Dataset.get_nearest_examples(indexed, "embedding", query, k: 2)

      assert length(scores) == 2
      assert length(examples) == 2

      # First result should be id=1 (exact match)
      assert hd(examples)["id"] == 1
    end

    test "raises if no index" do
      dataset = Dataset.from_list([%{"id" => 1}])

      assert_raise ArgumentError, ~r/No index found/, fn ->
        Dataset.get_nearest_examples(dataset, "embedding", Nx.tensor([1.0]))
      end
    end
  end

  describe "drop_index/2" do
    test "removes index" do
      dataset = Dataset.from_list([
        %{"embedding" => [1.0, 0.0]}
      ])

      indexed = Dataset.add_index(dataset, "embedding")
      dropped = Dataset.drop_index(indexed, "embedding")

      assert get_in(dropped.metadata, [:indices, "embedding"]) == nil
    end
  end
end
```

### Step 2: Run Tests

```bash
mix test test/dataset_manager/index/brute_force_test.exs
mix test test/dataset_manager/dataset_search_test.exs
```

### Step 3: Implement Until Tests Pass

### Step 4: Quality Checks

```bash
mix format
mix credo --strict
mix dialyzer
mix test
```

## Acceptance Criteria

- [ ] All tests pass
- [ ] `mix format` produces no changes
- [ ] `mix credo --strict` reports no issues
- [ ] `mix dialyzer` reports no errors
- [ ] Cosine similarity search works correctly
- [ ] L2 distance search works correctly
- [ ] Index save/load round-trips correctly

## Files to Create/Modify

| File | Action |
|------|--------|
| `lib/dataset_manager/index.ex` | Create behaviour |
| `lib/dataset_manager/index/brute_force.ex` | Create |
| `lib/dataset_manager/dataset.ex` | Add search methods |
| `test/dataset_manager/index/brute_force_test.exs` | Create |
| `test/dataset_manager/dataset_search_test.exs` | Create |

## Dependencies

- `nx` - Required for tensor operations (already added)

## Notes

For production use with large datasets:
1. Consider chunked/batched search for memory efficiency
2. Consider GPU acceleration via EXLA backend
3. Consider external vector database (Qdrant, Pinecone) for scale
