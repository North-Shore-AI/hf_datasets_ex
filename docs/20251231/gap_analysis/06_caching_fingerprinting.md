# Gap Analysis: Caching and Fingerprinting

## Overview

The Python `datasets` library has a sophisticated caching and fingerprinting system that tracks transformations and enables cache reuse. The Elixir port has basic caching but lacks fingerprinting.

## Current Elixir Implementation

```elixir
# lib/dataset_manager/cache.ex
defmodule HfDatasetsEx.Cache do
  # Simple file-based cache
  # Location: ~/.hf_datasets_ex/datasets/
  # Format: ETF binary

  @cache_dir Path.expand("~/.hf_datasets_ex/datasets")

  def get(cache_key) do
    path = cache_path(cache_key)
    if File.exists?(path) do
      {:ok, :erlang.binary_to_term(File.read!(path))}
    else
      :miss
    end
  end

  def put(cache_key, dataset) do
    path = cache_path(cache_key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary(dataset))
  end
end
```

## Missing Features

### P2 - Fingerprinting System

Python's fingerprinting tracks:
1. Input data hash
2. Function/transformation hash
3. Function arguments hash
4. Random state (seeds)

```python
# Python fingerprint.py
def generate_fingerprint(func, *args, **kwargs):
    hasher = Hasher()
    hasher.update(func)
    hasher.update(args)
    hasher.update(kwargs)
    return hasher.hexdigest()
```

```elixir
# Proposed Elixir
defmodule HfDatasetsEx.Fingerprint do
  @type t :: String.t()  # SHA256 hex string

  @doc """
  Generate fingerprint for a transformation.
  """
  @spec generate(atom(), list(), keyword()) :: t()
  def generate(operation, args, opts \\ []) do
    data = %{
      operation: operation,
      args: normalize_args(args),
      opts: normalize_opts(opts),
      version: HfDatasetsEx.version()
    }

    data
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Combine fingerprints (for chained operations).
  """
  @spec combine(t(), t()) :: t()
  def combine(fp1, fp2) do
    :crypto.hash(:sha256, fp1 <> fp2)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Generate fingerprint for dataset content.
  """
  @spec from_dataset(HfDatasetsEx.Dataset.t()) :: t()
  def from_dataset(%Dataset{items: items}) do
    # Hash first and last N items + count for efficiency
    sample = sample_items(items, 10)
    count = length(items)

    %{sample: sample, count: count}
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_args(args) do
    Enum.map(args, fn
      fun when is_function(fun) ->
        # Hash function source if available, otherwise use ref
        :erlang.fun_info(fun)[:module]
      other ->
        other
    end)
  end

  defp normalize_opts(opts) do
    opts
    |> Keyword.drop([:cache_file])  # Remove cache-specific opts
    |> Enum.sort()
  end

  defp sample_items(items, n) when length(items) <= n * 2 do
    items
  end

  defp sample_items(items, n) do
    first = Enum.take(items, n)
    last = items |> Enum.reverse() |> Enum.take(n) |> Enum.reverse()
    first ++ last
  end
end
```

### P2 - Transformation Cache

Cache results of transformations based on fingerprints.

```elixir
defmodule HfDatasetsEx.TransformCache do
  @cache_dir Path.expand("~/.hf_datasets_ex/transforms")

  @type cache_key :: {Fingerprint.t(), Fingerprint.t()}  # {input_fp, transform_fp}

  @spec get(Fingerprint.t(), Fingerprint.t()) :: {:ok, Dataset.t()} | :miss
  def get(input_fp, transform_fp) do
    key = combine_key(input_fp, transform_fp)
    path = cache_path(key)

    if File.exists?(path) do
      {:ok, load_cached(path)}
    else
      :miss
    end
  end

  @spec put(Fingerprint.t(), Fingerprint.t(), Dataset.t()) :: :ok
  def put(input_fp, transform_fp, dataset) do
    key = combine_key(input_fp, transform_fp)
    path = cache_path(key)

    File.mkdir_p!(Path.dirname(path))
    save_cached(path, dataset)

    # Update manifest
    update_manifest(key, %{
      created_at: DateTime.utc_now(),
      input_fingerprint: input_fp,
      transform_fingerprint: transform_fp,
      num_items: Dataset.num_items(dataset),
      size_bytes: File.stat!(path).size
    })

    :ok
  end

  @spec cleanup(keyword()) :: {:ok, non_neg_integer()}
  def cleanup(opts \\ []) do
    max_age_days = Keyword.get(opts, :max_age_days, 30)
    max_size_bytes = Keyword.get(opts, :max_size_bytes, 10 * 1024 * 1024 * 1024)  # 10GB

    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days, :day)

    manifest = load_manifest()

    # Find expired entries
    {expired, valid} =
      Enum.split_with(manifest, fn {_key, meta} ->
        DateTime.compare(meta.created_at, cutoff) == :lt
      end)

    # Delete expired
    deleted =
      Enum.map(expired, fn {key, _} ->
        path = cache_path(key)
        File.rm(path)
        key
      end)

    # If still over size, delete oldest
    remaining =
      if total_size(valid) > max_size_bytes do
        valid
        |> Enum.sort_by(fn {_, meta} -> meta.created_at end)
        |> delete_until_under_size(max_size_bytes)
      else
        valid
      end

    save_manifest(Map.new(remaining))

    {:ok, length(deleted)}
  end

  defp combine_key(input_fp, transform_fp) do
    "#{input_fp}_#{transform_fp}"
  end

  defp cache_path(key) do
    Path.join(@cache_dir, "#{key}.cache")
  end
end
```

### P2 - Cached Dataset Operations

Integrate fingerprinting with dataset operations.

```elixir
defmodule HfDatasetsEx.Dataset do
  # Add fingerprint to struct
  defstruct [
    :name,
    :version,
    :items,
    :metadata,
    :features,
    :fingerprint  # Add this
  ]

  @doc """
  Map with caching based on fingerprint.
  """
  @spec map(t(), (map() -> map()), keyword()) :: t()
  def map(%__MODULE__{} = dataset, fun, opts \\ []) do
    use_cache = Keyword.get(opts, :cache, true)

    if use_cache do
      map_cached(dataset, fun, opts)
    else
      map_uncached(dataset, fun, opts)
    end
  end

  defp map_cached(dataset, fun, opts) do
    input_fp = dataset.fingerprint || Fingerprint.from_dataset(dataset)
    transform_fp = Fingerprint.generate(:map, [fun], opts)

    case TransformCache.get(input_fp, transform_fp) do
      {:ok, cached} ->
        cached
      :miss ->
        result = map_uncached(dataset, fun, opts)
        new_fp = Fingerprint.combine(input_fp, transform_fp)
        result = %{result | fingerprint: new_fp}
        TransformCache.put(input_fp, transform_fp, result)
        result
    end
  end

  defp map_uncached(dataset, fun, opts) do
    new_items =
      if Keyword.get(opts, :batched, false) do
        batch_size = Keyword.get(opts, :batch_size, 1000)
        dataset.items
        |> Enum.chunk_every(batch_size)
        |> Enum.flat_map(fun)
      else
        Enum.map(dataset.items, fun)
      end

    %{dataset | items: new_items}
  end
end
```

### P3 - Cache Configuration

```elixir
defmodule HfDatasetsEx.Config do
  @default_config %{
    cache_enabled: true,
    cache_dir: "~/.hf_datasets_ex",
    max_cache_size_gb: 10,
    max_cache_age_days: 30,
    use_arrow_cache: false  # Use Arrow format for cache instead of ETF
  }

  @spec get(atom()) :: any()
  def get(key) do
    Application.get_env(:hf_datasets_ex, key, Map.get(@default_config, key))
  end

  @spec cache_enabled?() :: boolean()
  def cache_enabled? do
    get(:cache_enabled) and not offline_mode?()
  end

  @spec offline_mode?() :: boolean()
  def offline_mode? do
    System.get_env("HF_DATASETS_OFFLINE") == "1"
  end
end
```

### P3 - Download Caching

```elixir
defmodule HfDatasetsEx.DownloadCache do
  @doc """
  Check if file is cached and valid.
  """
  @spec get(String.t(), keyword()) :: {:ok, Path.t()} | :miss
  def get(url, opts \\ []) do
    etag = Keyword.get(opts, :etag)
    cache_path = url_to_cache_path(url)

    cond do
      not File.exists?(cache_path) -> :miss
      etag && not etag_matches?(cache_path, etag) -> :miss
      true -> {:ok, cache_path}
    end
  end

  @spec put(String.t(), binary(), keyword()) :: {:ok, Path.t()}
  def put(url, content, opts \\ []) do
    etag = Keyword.get(opts, :etag)
    cache_path = url_to_cache_path(url)

    File.mkdir_p!(Path.dirname(cache_path))
    File.write!(cache_path, content)

    if etag do
      save_etag(cache_path, etag)
    end

    {:ok, cache_path}
  end

  defp url_to_cache_path(url) do
    hash = :crypto.hash(:sha256, url) |> Base.encode16(case: :lower)
    Path.join([Config.get(:cache_dir), "downloads", hash])
  end
end
```

## Cache Directory Structure

```
~/.hf_datasets_ex/
├── datasets/                    # Loaded datasets
│   ├── openai--gsm8k/
│   │   ├── main/
│   │   │   ├── train.cache
│   │   │   └── test.cache
│   │   └── manifest.json
│   └── allenai--mmlu/
│       └── ...
├── transforms/                  # Transformation cache
│   ├── a1b2c3d4_e5f6g7h8.cache
│   └── manifest.json
├── downloads/                   # Raw download cache
│   ├── abcd1234.../
│   │   ├── data
│   │   └── etag
│   └── ...
└── config.json                  # User configuration
```

## Files to Create/Modify

| File | Purpose |
|------|---------|
| `lib/dataset_manager/fingerprint.ex` | Fingerprinting system |
| `lib/dataset_manager/transform_cache.ex` | Transformation caching |
| `lib/dataset_manager/download_cache.ex` | Download caching (extend existing) |
| `lib/dataset_manager/config.ex` | Configuration management |
| `lib/dataset_manager/cache.ex` | Update existing cache module |
| `test/dataset_manager/fingerprint_test.exs` | Fingerprint tests |
| `test/dataset_manager/transform_cache_test.exs` | Cache tests |

## Testing Requirements

```elixir
defmodule HfDatasetsEx.FingerprintTest do
  use ExUnit.Case

  alias HfDatasetsEx.Fingerprint

  test "same inputs produce same fingerprint" do
    fp1 = Fingerprint.generate(:map, [&String.upcase/1], [])
    fp2 = Fingerprint.generate(:map, [&String.upcase/1], [])

    assert fp1 == fp2
  end

  test "different inputs produce different fingerprints" do
    fp1 = Fingerprint.generate(:map, [&String.upcase/1], [])
    fp2 = Fingerprint.generate(:map, [&String.downcase/1], [])

    assert fp1 != fp2
  end

  test "combine is order-dependent" do
    fp1 = Fingerprint.generate(:map, [&String.upcase/1], [])
    fp2 = Fingerprint.generate(:filter, [& &1["valid"]], [])

    combined1 = Fingerprint.combine(fp1, fp2)
    combined2 = Fingerprint.combine(fp2, fp1)

    assert combined1 != combined2
  end
end

defmodule HfDatasetsEx.TransformCacheTest do
  use ExUnit.Case

  alias HfDatasetsEx.{Dataset, TransformCache, Fingerprint}

  setup do
    # Use temp directory for tests
    cache_dir = System.tmp_dir!() |> Path.join("hf_datasets_test")
    Application.put_env(:hf_datasets_ex, :cache_dir, cache_dir)

    on_exit(fn -> File.rm_rf!(cache_dir) end)

    :ok
  end

  test "cache hit returns cached dataset" do
    dataset = Dataset.from_list([%{"x" => 1}])
    input_fp = Fingerprint.from_dataset(dataset)
    transform_fp = Fingerprint.generate(:map, [], [])

    TransformCache.put(input_fp, transform_fp, dataset)

    assert {:ok, cached} = TransformCache.get(input_fp, transform_fp)
    assert cached.items == dataset.items
  end

  test "cache miss returns :miss" do
    assert :miss = TransformCache.get("nonexistent", "also_nonexistent")
  end
end
```

## Dependencies

No new dependencies required. Uses:
- `:crypto` (Erlang stdlib) for hashing
- `File` for cache storage
- `Jason` for manifest JSON

## Performance Considerations

1. **Hash Efficiency**: Sample items for large datasets instead of hashing all
2. **Lazy Fingerprinting**: Only compute fingerprint when caching is used
3. **Background Cleanup**: Run cache cleanup in separate process
4. **Memory Mapping**: Consider mmap for large cached files
5. **Compression**: Compress cached data with `:zstd` or `:lz4`
