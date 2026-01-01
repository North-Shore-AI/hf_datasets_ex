# Gap Analysis: Search and Indexing

## Overview

The Python `datasets` library supports full-text and vector similarity search via FAISS and Elasticsearch integrations. The Elixir port has no search functionality.

## Python Search Features

```python
# datasets/search.py

# Vector similarity search (FAISS)
dataset.add_faiss_index(column="embeddings", string_factory="Flat")
scores, examples = dataset.get_nearest_examples("embeddings", query_vector, k=10)
dataset.save_faiss_index("embeddings", "index.faiss")
dataset.load_faiss_index("embeddings", "index.faiss")
dataset.drop_index("embeddings")

# Full-text search (Elasticsearch)
dataset.add_elasticsearch_index(column="text", es_client=es)
scores, examples = dataset.search("text", "query string", k=10)
```

## FAISS Integration (P3)

### Overview

FAISS (Facebook AI Similarity Search) provides efficient similarity search for dense vectors. Options for Elixir:

1. **NIF wrapper** - Wrap FAISS C++ library
2. **Port** - External FAISS server
3. **Pure Elixir** - Implement basic algorithms
4. **External service** - Use Pinecone, Weaviate, Qdrant, Milvus

### Proposed Architecture

```elixir
defmodule HfDatasetsEx.Index.FAISS do
  @moduledoc """
  FAISS vector index for similarity search.

  Requires faiss_ex NIF or external FAISS service.
  """

  @type t :: %__MODULE__{
    column: String.t(),
    dimension: non_neg_integer(),
    index_type: atom(),
    metric: atom(),
    index_ref: reference() | nil
  }

  defstruct [:column, :dimension, :index_type, :metric, :index_ref]

  @type index_type :: :flat | :ivf_flat | :hnsw | :pq

  @doc """
  Create a new FAISS index.

  ## Options

    * `:index_type` - Index type (:flat, :ivf_flat, :hnsw, :pq)
    * `:metric` - Distance metric (:l2, :inner_product)
    * `:nlist` - Number of clusters for IVF (default: 100)
    * `:nprobe` - Number of clusters to search (default: 10)
    * `:m` - Number of connections for HNSW (default: 32)

  """
  @spec new(String.t(), non_neg_integer(), keyword()) :: t()
  def new(column, dimension, opts \\ []) do
    index_type = Keyword.get(opts, :index_type, :flat)
    metric = Keyword.get(opts, :metric, :l2)

    %__MODULE__{
      column: column,
      dimension: dimension,
      index_type: index_type,
      metric: metric,
      index_ref: nil
    }
  end

  @doc """
  Add vectors to the index.
  """
  @spec add(t(), Nx.Tensor.t()) :: t()
  def add(%__MODULE__{} = index, vectors) do
    # Validate dimensions
    {n, d} = Nx.shape(vectors)

    if d != index.dimension do
      raise ArgumentError, "Vector dimension #{d} doesn't match index dimension #{index.dimension}"
    end

    # Add to FAISS via NIF
    new_ref = FaissNIF.add(index.index_ref, Nx.to_binary(vectors), n, d)

    %{index | index_ref: new_ref}
  end

  @doc """
  Search for k nearest neighbors.
  """
  @spec search(t(), Nx.Tensor.t(), non_neg_integer()) :: {Nx.Tensor.t(), Nx.Tensor.t()}
  def search(%__MODULE__{} = index, query, k) do
    # Returns {distances, indices}
    {dist_binary, idx_binary} = FaissNIF.search(index.index_ref, Nx.to_binary(query), k)

    distances = Nx.from_binary(dist_binary, :f32) |> Nx.reshape({:auto, k})
    indices = Nx.from_binary(idx_binary, :s64) |> Nx.reshape({:auto, k})

    {distances, indices}
  end

  @doc """
  Save index to file.
  """
  @spec save(t(), Path.t()) :: :ok
  def save(%__MODULE__{} = index, path) do
    FaissNIF.save(index.index_ref, path)
  end

  @doc """
  Load index from file.
  """
  @spec load(Path.t()) :: t()
  def load(path) do
    ref = FaissNIF.load(path)
    # Get metadata from loaded index
    %__MODULE__{index_ref: ref}
  end
end
```

### Pure Elixir Fallback

For environments without FAISS NIF:

```elixir
defmodule HfDatasetsEx.Index.BruteForce do
  @moduledoc """
  Pure Elixir brute-force similarity search.

  Slower than FAISS but works everywhere.
  """

  @type t :: %__MODULE__{
    column: String.t(),
    vectors: Nx.Tensor.t() | nil,
    metric: atom()
  }

  defstruct [:column, :vectors, :metric]

  def new(column, opts \\ []) do
    %__MODULE__{
      column: column,
      vectors: nil,
      metric: Keyword.get(opts, :metric, :l2)
    }
  end

  def add(%__MODULE__{vectors: nil} = index, vectors) do
    %{index | vectors: vectors}
  end

  def add(%__MODULE__{vectors: existing} = index, vectors) do
    %{index | vectors: Nx.concatenate([existing, vectors], axis: 0)}
  end

  def search(%__MODULE__{vectors: vectors, metric: metric} = _index, query, k) do
    # Compute all pairwise distances
    distances = case metric do
      :l2 -> l2_distance(query, vectors)
      :inner_product -> inner_product(query, vectors)
      :cosine -> cosine_similarity(query, vectors)
    end

    # Get top k
    {top_distances, top_indices} = Nx.top_k(distances, k: k)

    {top_distances, top_indices}
  end

  defp l2_distance(query, vectors) do
    # query: [d], vectors: [n, d]
    diff = Nx.subtract(vectors, query)
    Nx.sum(Nx.multiply(diff, diff), axes: [1])
  end

  defp inner_product(query, vectors) do
    Nx.dot(vectors, query)
  end

  defp cosine_similarity(query, vectors) do
    query_norm = Nx.sqrt(Nx.sum(Nx.multiply(query, query)))
    vector_norms = Nx.sqrt(Nx.sum(Nx.multiply(vectors, vectors), axes: [1]))

    Nx.divide(Nx.dot(vectors, query), Nx.multiply(query_norm, vector_norms))
  end
end
```

### Dataset Integration

```elixir
defmodule HfDatasetsEx.Dataset do
  @doc """
  Add a FAISS index for similarity search.
  """
  @spec add_faiss_index(t(), String.t(), keyword()) :: t()
  def add_faiss_index(%__MODULE__{} = dataset, column, opts \\ []) do
    # Extract vectors from column
    vectors =
      dataset.items
      |> Enum.map(&Map.get(&1, column))
      |> Nx.stack()

    {_n, d} = Nx.shape(vectors)

    # Create and populate index
    index =
      Index.FAISS.new(column, d, opts)
      |> Index.FAISS.add(vectors)

    # Store index in dataset
    indices = Map.get(dataset.metadata, :indices, %{})
    metadata = Map.put(dataset.metadata, :indices, Map.put(indices, column, index))

    %{dataset | metadata: metadata}
  end

  @doc """
  Search for nearest examples.
  """
  @spec get_nearest_examples(t(), String.t(), Nx.Tensor.t(), keyword()) ::
    {[float()], [map()]}
  def get_nearest_examples(%__MODULE__{} = dataset, column, query, opts \\ []) do
    k = Keyword.get(opts, :k, 10)

    index = get_in(dataset.metadata, [:indices, column])

    unless index do
      raise ArgumentError, "No index found for column #{column}. Call add_faiss_index first."
    end

    {distances, indices} = Index.FAISS.search(index, query, k)

    # Fetch examples
    examples =
      indices
      |> Nx.to_flat_list()
      |> Enum.map(&Enum.at(dataset.items, &1))

    scores = Nx.to_flat_list(distances)

    {scores, examples}
  end

  @doc """
  Save FAISS index to file.
  """
  @spec save_faiss_index(t(), String.t(), Path.t()) :: :ok
  def save_faiss_index(%__MODULE__{} = dataset, column, path) do
    index = get_in(dataset.metadata, [:indices, column])
    Index.FAISS.save(index, path)
  end

  @doc """
  Load FAISS index from file.
  """
  @spec load_faiss_index(t(), String.t(), Path.t()) :: t()
  def load_faiss_index(%__MODULE__{} = dataset, column, path) do
    index = Index.FAISS.load(path)
    index = %{index | column: column}

    indices = Map.get(dataset.metadata, :indices, %{})
    metadata = Map.put(dataset.metadata, :indices, Map.put(indices, column, index))

    %{dataset | metadata: metadata}
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

## Elasticsearch Integration (P3)

### Overview

Elasticsearch provides full-text search. Options for Elixir:

1. **elasticsearch** - Hex package
2. **elastix** - Alternative Hex package
3. **tirexs** - Another option
4. **Direct HTTP** - Use Req/HTTPoison

### Proposed Architecture

```elixir
defmodule HfDatasetsEx.Index.Elasticsearch do
  @moduledoc """
  Elasticsearch index for full-text search.
  """

  @type t :: %__MODULE__{
    column: String.t(),
    es_client: module(),
    index_name: String.t(),
    es_config: map()
  }

  defstruct [:column, :es_client, :index_name, :es_config]

  @spec new(String.t(), keyword()) :: t()
  def new(column, opts \\ []) do
    %__MODULE__{
      column: column,
      es_client: Keyword.get(opts, :es_client, Elasticsearch),
      index_name: Keyword.get(opts, :index_name, "hf_datasets_#{column}"),
      es_config: Keyword.get(opts, :es_config, %{url: "http://localhost:9200"})
    }
  end

  @spec index_documents(t(), [map()]) :: :ok
  def index_documents(%__MODULE__{} = index, documents) do
    # Bulk index documents
    bulk_body =
      documents
      |> Enum.with_index()
      |> Enum.flat_map(fn {doc, idx} ->
        [
          %{index: %{_index: index.index_name, _id: idx}},
          %{content: Map.get(doc, index.column)}
        ]
      end)
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")

    Elasticsearch.post("/_bulk", bulk_body <> "\n", index.es_config)

    :ok
  end

  @spec search(t(), String.t(), keyword()) :: {[float()], [non_neg_integer()]}
  def search(%__MODULE__{} = index, query, opts \\ []) do
    k = Keyword.get(opts, :k, 10)

    body = %{
      query: %{
        match: %{
          content: query
        }
      },
      size: k
    }

    {:ok, response} = Elasticsearch.post(
      "/#{index.index_name}/_search",
      Jason.encode!(body),
      index.es_config
    )

    hits = response["hits"]["hits"]

    scores = Enum.map(hits, & &1["_score"])
    indices = Enum.map(hits, &String.to_integer(&1["_id"]))

    {scores, indices}
  end
end
```

### Dataset Integration

```elixir
defmodule HfDatasetsEx.Dataset do
  @doc """
  Add an Elasticsearch index for full-text search.
  """
  @spec add_elasticsearch_index(t(), String.t(), keyword()) :: t()
  def add_elasticsearch_index(%__MODULE__{} = dataset, column, opts \\ []) do
    index = Index.Elasticsearch.new(column, opts)

    # Index all documents
    Index.Elasticsearch.index_documents(index, dataset.items)

    # Store index reference
    indices = Map.get(dataset.metadata, :es_indices, %{})
    metadata = Map.put(dataset.metadata, :es_indices, Map.put(indices, column, index))

    %{dataset | metadata: metadata}
  end

  @doc """
  Full-text search using Elasticsearch.
  """
  @spec search(t(), String.t(), String.t(), keyword()) :: {[float()], [map()]}
  def search(%__MODULE__{} = dataset, column, query, opts \\ []) do
    index = get_in(dataset.metadata, [:es_indices, column])

    unless index do
      raise ArgumentError, "No Elasticsearch index for column #{column}"
    end

    {scores, indices} = Index.Elasticsearch.search(index, query, opts)

    examples = Enum.map(indices, &Enum.at(dataset.items, &1))

    {scores, examples}
  end
end
```

## Alternative: Qdrant Integration

Qdrant is a vector database with a REST API that's easier to integrate:

```elixir
defmodule HfDatasetsEx.Index.Qdrant do
  @moduledoc """
  Qdrant vector database integration.

  Qdrant provides a REST API for vector similarity search.
  """

  @type t :: %__MODULE__{
    collection: String.t(),
    url: String.t(),
    dimension: non_neg_integer()
  }

  defstruct [:collection, :url, :dimension]

  @spec new(String.t(), non_neg_integer(), keyword()) :: t()
  def new(collection, dimension, opts \\ []) do
    %__MODULE__{
      collection: collection,
      dimension: dimension,
      url: Keyword.get(opts, :url, "http://localhost:6333")
    }
  end

  @spec create_collection(t()) :: :ok
  def create_collection(%__MODULE__{} = index) do
    body = %{
      vectors: %{
        size: index.dimension,
        distance: "Cosine"
      }
    }

    Req.put!("#{index.url}/collections/#{index.collection}", json: body)
    :ok
  end

  @spec upsert(t(), [map()]) :: :ok
  def upsert(%__MODULE__{} = index, points) do
    body = %{
      points: Enum.map(points, fn point ->
        %{
          id: point.id,
          vector: Nx.to_flat_list(point.vector),
          payload: point.payload
        }
      end)
    }

    Req.put!("#{index.url}/collections/#{index.collection}/points", json: body)
    :ok
  end

  @spec search(t(), Nx.Tensor.t(), non_neg_integer()) :: [map()]
  def search(%__MODULE__{} = index, query, k) do
    body = %{
      vector: Nx.to_flat_list(query),
      limit: k,
      with_payload: true
    }

    response = Req.post!("#{index.url}/collections/#{index.collection}/points/search", json: body)

    response.body["result"]
  end
end
```

## Files to Create

| File | Purpose | Priority |
|------|---------|----------|
| `lib/dataset_manager/index.ex` | Index behaviour and registry | P3 |
| `lib/dataset_manager/index/brute_force.ex` | Pure Elixir fallback | P3 |
| `lib/dataset_manager/index/faiss.ex` | FAISS wrapper (if NIF available) | P3 |
| `lib/dataset_manager/index/elasticsearch.ex` | ES integration | P3 |
| `lib/dataset_manager/index/qdrant.ex` | Qdrant integration | P3 |
| `test/dataset_manager/index_test.exs` | Index tests | P3 |

## Dependencies

| Feature | Dependency | Notes |
|---------|------------|-------|
| FAISS | Custom NIF or `faiss_ex` | Complex, requires C++ |
| Elasticsearch | `elasticsearch` | Requires ES server |
| Qdrant | `req` (HTTP) | Easy, just REST API |
| BruteForce | `nx` | ✅ Already have |

## Testing Requirements

```elixir
defmodule HfDatasetsEx.Index.BruteForceTest do
  use ExUnit.Case

  alias HfDatasetsEx.Index.BruteForce

  test "search returns k nearest" do
    vectors = Nx.tensor([
      [1.0, 0.0],
      [0.0, 1.0],
      [1.0, 1.0]
    ])

    index =
      BruteForce.new("embeddings")
      |> BruteForce.add(vectors)

    query = Nx.tensor([1.0, 0.1])

    {distances, indices} = BruteForce.search(index, query, k: 2)

    # First result should be [1.0, 0.0]
    assert Nx.to_number(indices[0]) == 0
  end
end
```

## Recommendations

Given complexity and P3 priority:

1. **Start with BruteForce** - Pure Elixir, works everywhere
2. **Add Qdrant support** - Easy REST API, no NIF needed
3. **Consider FAISS NIF later** - Only if performance critical
4. **Skip Elasticsearch initially** - Use Qdrant's payload filtering instead

This provides similarity search capability with minimal dependencies.
