# Python datasets Library - Detailed Comparison

## Overview

This document provides a detailed comparison between the Python `datasets` library (v4.4.3) and the Elixir `hf_datasets_ex` port (v0.1.2).

## Core Philosophy Differences

| Aspect | Python datasets | hf_datasets_ex |
|--------|----------------|----------------|
| Data Storage | Apache Arrow tables | Elixir lists of maps |
| Mutation | In-place with copy-on-write | Fully immutable |
| Memory Mapping | Native support | Not applicable |
| Parallelism | multiprocessing (num_proc) | Task.async_stream |
| Streaming | IterableDataset | IterableDataset (Streams) |
| Type System | Dynamic with Features | Dynamic with Features |

## Architectural Differences

### Data Representation

**Python**: Uses Apache Arrow tables internally with memory mapping for large datasets:
```python
# Internal structure
dataset._data: Table  # PyArrow Table
dataset._fingerprint: str
dataset._format_type: str
```

**Elixir**: Uses simple Elixir data structures:
```elixir
%Dataset{
  items: [map()],           # List of maps
  features: Features.t(),    # Schema
  fingerprint: String.t(),   # Cache key
  format: atom()             # Output format
}
```

### Memory Efficiency

**Python**: Memory-mapped Arrow files allow working with datasets larger than RAM.

**Elixir**: Data must fit in memory for `Dataset`, use `IterableDataset` for streaming large files.

### Parallelism

**Python**:
```python
dataset.map(fn, num_proc=4)  # Uses multiprocessing
```

**Elixir**:
```elixir
# Parallelism via Stream
dataset.items
|> Task.async_stream(&process/1, max_concurrency: 4)
|> Enum.to_list()
```

## Feature Parity Matrix

### Load Functions

| Function | Python | Elixir | Notes |
|----------|--------|--------|-------|
| `load_dataset(path)` | datasets | `HfDatasetsEx.load_dataset/2` | Full support |
| `load_from_disk(path)` | datasets | `Export.Disk.load_dataset/1` | New |
| `load_dataset(path, streaming=True)` | datasets | Returns `IterableDataset` | Via option |

### Dataset Operations

| Operation | Python | Elixir | Compatibility |
|-----------|--------|--------|---------------|
| `map(fn)` | Full | `Dataset.map/3` | Compatible |
| `filter(fn)` | Full | `Dataset.filter/3` | Compatible |
| `select(indices)` | Full | `Dataset.select/2` | Compatible |
| `shuffle(seed=42)` | NumPy RNG | PCG64 PRNG | Exact match |
| `sort(column)` | Full | `Dataset.sort/3` | Compatible |
| `train_test_split()` | Full | `Dataset.train_test_split/2` | With stratify |
| `shard(num_shards, index)` | Full | `Dataset.shard/2` | Compatible |

### Export Functions

| Function | Python | Elixir | Notes |
|----------|--------|--------|-------|
| `to_csv()` | Full | `Export.to_csv/3` | Full support |
| `to_json()` | Full | `Export.to_json/3` | Full support |
| `to_parquet()` | Full | `Export.to_parquet/3` | Full support |
| `save_to_disk()` | Full | `Export.Disk.save_dataset/2` | New |
| `push_to_hub()` | Full | `Hub.push_to_hub/3` | Full support |

### Feature Types

| Type | Python | Elixir | Notes |
|------|--------|--------|-------|
| Value | Full | `Features.Value` | All dtypes |
| ClassLabel | Full | `Features.ClassLabel` | Full support |
| Sequence | Full | `Features.Sequence` | Full support |
| Image | Full | `Features.Image` | Full support |
| Audio | Full | `Features.Audio` | Full support |
| Array2D-5D | Full | `Features.Array` | Unified type |
| Translation | Full | `Features.Translation` | Full support |

## API Differences

### Loading Datasets

**Python**:
```python
from datasets import load_dataset

# From Hub
ds = load_dataset("squad")

# Local file
ds = load_dataset("json", data_files="data.json")

# Streaming
ds = load_dataset("squad", streaming=True)
```

**Elixir**:
```elixir
# From Hub
{:ok, dd} = HfDatasetsEx.load_dataset("squad")

# Local file
{:ok, dataset} = Dataset.from_json("data.json")

# Streaming
{:ok, iterable} = HfDatasetsEx.load_dataset("squad", streaming: true)
```

### Transformations

**Python**:
```python
ds = ds.map(lambda x: {"upper": x["text"].upper()})
ds = ds.filter(lambda x: len(x["text"]) > 10)
ds = ds.shuffle(seed=42)
```

**Elixir**:
```elixir
dataset = Dataset.map(dataset, fn item ->
  Map.put(item, "upper", String.upcase(item["text"]))
end)

dataset = Dataset.filter(dataset, fn item ->
  String.length(item["text"]) > 10
end)

dataset = Dataset.shuffle(dataset, seed: 42)
```

### Format Setting

**Python**:
```python
ds.set_format("torch", columns=["input_ids", "labels"])
for batch in ds:
    # batch contains torch.Tensors
```

**Elixir**:
```elixir
dataset = Dataset.set_format(dataset, :nx, columns: ["input_ids", "labels"])

for item <- dataset do
  # item contains Nx.Tensor values
end

# Or with batching
dataset
|> Dataset.iter(batch_size: 32)
|> Enum.each(fn batch ->
  # batch is %{"input_ids" => Nx.Tensor, "labels" => Nx.Tensor}
end)
```

### Caching

**Python**:
```python
# Automatic fingerprint-based caching
ds = ds.map(fn, cache_file_name="cached.arrow")

# Disable caching
ds = ds.map(fn, load_from_cache_file=False)
```

**Elixir**:
```elixir
# Automatic fingerprint-based caching (enabled by default)
dataset = Dataset.map(dataset, fn, cache: true)

# Disable caching
dataset = Dataset.map(dataset, fn, cache: false)
```

## Missing Python Features (Summary)

### Not Planned

- `num_proc` parameter: Elixir handles concurrency differently
- Memory mapping: Not applicable to Elixir data model
- TensorFlow/PyTorch direct integration: Use Nx instead
- Spark integration: Out of scope

### Lower Priority

- FAISS/Elasticsearch: Use external services
- HDF5 format: Specialized use case
- Video/PDF features: Require NIFs

## Recommended Migration Path

### From Python to Elixir

1. Use same data files (Parquet, JSON, CSV work identically)
2. Replace `load_dataset` with `HfDatasetsEx.load_dataset`
3. Replace lambda functions with Elixir anonymous functions
4. Use `Dataset.set_format(:nx)` instead of `set_format("torch")`
5. Use `Dataset.iter/2` for batch iteration

### Shuffle Compatibility

Both use PCG64 PRNG with same seeding:
```python
# Python
ds.shuffle(seed=42)
```

```elixir
# Elixir - produces same order
Dataset.shuffle(dataset, seed: 42)
```

## Performance Considerations

| Operation | Python | Elixir | Notes |
|-----------|--------|--------|-------|
| Large dataset load | Memory mapped | Must fit in RAM | Use IterableDataset |
| Map operations | multiprocessing | Single process | Use Task.async_stream manually |
| Shuffle | NumPy in-memory | PCG64 in-memory | Same algorithm |
| Filter | C optimized | Elixir Enum | Slightly slower |
| Hub upload | requests | Req | Similar |

For large datasets:
- Python advantage: Memory mapping
- Elixir advantage: Simpler streaming with IterableDataset
