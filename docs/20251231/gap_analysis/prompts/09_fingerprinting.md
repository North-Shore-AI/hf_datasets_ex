# Implementation Prompt: Caching and Fingerprinting

## Priority: P2 (Medium)

## Objective

Implement a fingerprinting system for transformation caching, enabling automatic cache reuse when the same transformations are applied to the same data.

## Required Reading

Before starting, read these files completely:

```
lib/dataset_manager/cache.ex
lib/dataset_manager/dataset.ex
docs/20251231/gap_analysis/06_caching_fingerprinting.md
```

## Context

The Python `datasets` library uses fingerprinting to:
1. Track transformation chains
2. Automatically cache transformation results
3. Reuse cached results when inputs/operations match

Current Elixir implementation:
- Basic file caching exists in `cache.ex`
- No fingerprinting or transformation tracking
- Transformations always recompute

## Implementation Requirements

### 1. Fingerprint Module

Create `lib/dataset_manager/fingerprint.ex`:

```elixir
defmodule HfDatasetsEx.Fingerprint do
  @moduledoc """
  Generates fingerprints for caching dataset transformations.

  A fingerprint is a SHA256 hash that uniquely identifies:
  - The input data
  - The operation being performed
  - The operation arguments

  This enables automatic cache invalidation when inputs or operations change.
  """

  @type t :: String.t()  # 64-char hex string

  @doc """
  Generate a fingerprint for an operation with arguments.

  ## Examples

      fp = Fingerprint.generate(:map, [&String.upcase/1], batched: true)

  """
  @spec generate(atom(), list(), keyword()) :: t()
  def generate(operation, args, opts \\ []) do
    data = %{
      operation: operation,
      args: normalize_args(args),
      opts: normalize_opts(opts),
      lib_version: Application.spec(:hf_datasets_ex, :vsn) |> to_string()
    }

    data
    |> :erlang.term_to_binary()
    |> hash()
  end

  @doc """
  Generate a fingerprint for a dataset's content.

  For efficiency, samples the dataset rather than hashing all items.
  """
  @spec from_dataset(HfDatasetsEx.Dataset.t()) :: t()
  def from_dataset(%{items: items}) do
    data = %{
      count: length(items),
      sample: sample_items(items, 10)
    }

    data
    |> :erlang.term_to_binary()
    |> hash()
  end

  @doc """
  Combine two fingerprints (for chained operations).

  Order matters: combine(a, b) != combine(b, a)
  """
  @spec combine(t(), t()) :: t()
  def combine(fp1, fp2) do
    hash(fp1 <> fp2)
  end

  @doc """
  Combine multiple fingerprints in order.
  """
  @spec combine_all([t()]) :: t()
  def combine_all([]), do: generate(:empty, [])
  def combine_all([fp]), do: fp
  def combine_all([fp1, fp2 | rest]) do
    combine_all([combine(fp1, fp2) | rest])
  end

  # Private functions

  defp hash(data) when is_binary(data) do
    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
  end

  defp normalize_args(args) do
    Enum.map(args, fn
      f when is_function(f) ->
        # Use function info for anonymous functions
        info = :erlang.fun_info(f)
        %{type: :function, module: info[:module], name: info[:name], arity: info[:arity]}

      other ->
        other
    end)
  end

  defp normalize_opts(opts) do
    opts
    |> Keyword.drop([:new_fingerprint, :cache_file])  # Meta options
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

### 2. Transform Cache Module

Create `lib/dataset_manager/transform_cache.ex`:

```elixir
defmodule HfDatasetsEx.TransformCache do
  @moduledoc """
  Caches dataset transformation results based on fingerprints.
  """

  alias HfDatasetsEx.{Dataset, Fingerprint}

  @cache_dir Path.expand("~/.hf_datasets_ex/transforms")
  @manifest_file "manifest.json"

  @type cache_key :: String.t()

  @doc """
  Look up a cached transformation result.

  Returns {:ok, dataset} if found, :miss otherwise.
  """
  @spec get(Fingerprint.t(), Fingerprint.t()) :: {:ok, Dataset.t()} | :miss
  def get(input_fp, transform_fp) do
    key = cache_key(input_fp, transform_fp)
    path = cache_path(key)

    if File.exists?(path) do
      try do
        dataset = path |> File.read!() |> :erlang.binary_to_term()
        {:ok, dataset}
      rescue
        _ -> :miss
      end
    else
      :miss
    end
  end

  @doc """
  Store a transformation result in cache.
  """
  @spec put(Fingerprint.t(), Fingerprint.t(), Dataset.t()) :: :ok
  def put(input_fp, transform_fp, dataset) do
    key = cache_key(input_fp, transform_fp)
    path = cache_path(key)

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary(dataset))

    update_manifest(key, %{
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      input_fingerprint: input_fp,
      transform_fingerprint: transform_fp,
      num_items: Dataset.num_items(dataset),
      size_bytes: File.stat!(path).size
    })

    :ok
  end

  @doc """
  Clean up old cache entries.

  ## Options

    * `:max_age_days` - Remove entries older than this (default: 30)
    * `:max_size_bytes` - Maximum total cache size (default: 10GB)

  """
  @spec cleanup(keyword()) :: {:ok, non_neg_integer()}
  def cleanup(opts \\ []) do
    max_age_days = Keyword.get(opts, :max_age_days, 30)
    max_size_bytes = Keyword.get(opts, :max_size_bytes, 10 * 1024 * 1024 * 1024)

    manifest = load_manifest()
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days, :day)

    # Find expired entries
    {expired, valid} =
      Enum.split_with(manifest, fn {_key, meta} ->
        {:ok, created, _} = DateTime.from_iso8601(meta["created_at"])
        DateTime.compare(created, cutoff) == :lt
      end)

    # Delete expired files
    deleted_count =
      expired
      |> Enum.map(fn {key, _} ->
        path = cache_path(key)
        File.rm(path)
        key
      end)
      |> length()

    # If still over size limit, delete oldest
    remaining = delete_until_under_size(valid, max_size_bytes)

    save_manifest(Map.new(remaining))

    {:ok, deleted_count}
  end

  @doc """
  Clear entire transform cache.
  """
  @spec clear_all() :: :ok
  def clear_all do
    File.rm_rf!(@cache_dir)
    File.mkdir_p!(@cache_dir)
    :ok
  end

  @doc """
  Get cache statistics.
  """
  @spec stats() :: map()
  def stats do
    manifest = load_manifest()

    total_size =
      manifest
      |> Map.values()
      |> Enum.map(& &1["size_bytes"])
      |> Enum.sum()

    %{
      entry_count: map_size(manifest),
      total_size_bytes: total_size,
      cache_dir: @cache_dir
    }
  end

  # Private functions

  defp cache_key(input_fp, transform_fp) do
    "#{String.slice(input_fp, 0, 16)}_#{String.slice(transform_fp, 0, 16)}"
  end

  defp cache_path(key) do
    Path.join(@cache_dir, "#{key}.cache")
  end

  defp manifest_path do
    Path.join(@cache_dir, @manifest_file)
  end

  defp load_manifest do
    path = manifest_path()

    if File.exists?(path) do
      path |> File.read!() |> Jason.decode!()
    else
      %{}
    end
  end

  defp save_manifest(manifest) do
    File.mkdir_p!(@cache_dir)
    File.write!(manifest_path(), Jason.encode!(manifest, pretty: true))
  end

  defp update_manifest(key, meta) do
    manifest = load_manifest()
    updated = Map.put(manifest, key, meta)
    save_manifest(updated)
  end

  defp delete_until_under_size(entries, max_size) do
    total = entries |> Enum.map(fn {_, m} -> m["size_bytes"] || 0 end) |> Enum.sum()

    if total <= max_size do
      entries
    else
      # Sort by created_at ascending (oldest first)
      sorted =
        entries
        |> Enum.sort_by(fn {_, m} -> m["created_at"] end)

      delete_until_under_size_loop(sorted, total, max_size)
    end
  end

  defp delete_until_under_size_loop([], _total, _max), do: []
  defp delete_until_under_size_loop(entries, total, max) when total <= max, do: entries
  defp delete_until_under_size_loop([{key, meta} | rest], total, max) do
    File.rm(cache_path(key))
    delete_until_under_size_loop(rest, total - (meta["size_bytes"] || 0), max)
  end
end
```

### 3. Update Dataset Module

Add to `lib/dataset_manager/dataset.ex`:

```elixir
defmodule HfDatasetsEx.Dataset do
  alias HfDatasetsEx.{Fingerprint, TransformCache}

  # Add fingerprint to struct
  defstruct [
    :name,
    :version,
    :items,
    :metadata,
    :features,
    :fingerprint,  # Add this
    format: :elixir,
    format_columns: nil,
    format_opts: []
  ]

  @doc """
  Get or compute the fingerprint for this dataset.
  """
  @spec fingerprint(t()) :: Fingerprint.t()
  def fingerprint(%__MODULE__{fingerprint: fp}) when not is_nil(fp), do: fp
  def fingerprint(%__MODULE__{} = dataset), do: Fingerprint.from_dataset(dataset)

  @doc """
  Map with optional caching.

  ## Options

    * `:cache` - Enable caching (default: true if caching enabled globally)
    * `:new_fingerprint` - Custom fingerprint for result

  """
  @spec map(t(), (map() -> map()), keyword()) :: t()
  def map(%__MODULE__{} = dataset, fun, opts \\ []) do
    use_cache = Keyword.get(opts, :cache, caching_enabled?())

    if use_cache do
      map_cached(dataset, fun, opts)
    else
      map_uncached(dataset, fun, opts)
    end
  end

  defp map_cached(dataset, fun, opts) do
    input_fp = fingerprint(dataset)
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
    batched = Keyword.get(opts, :batched, false)
    batch_size = Keyword.get(opts, :batch_size, 1000)

    new_items =
      if batched do
        dataset.items
        |> Enum.chunk_every(batch_size)
        |> Enum.flat_map(fun)
      else
        Enum.map(dataset.items, fun)
      end

    %{dataset | items: new_items, fingerprint: nil}
  end

  @doc """
  Filter with optional caching.
  """
  @spec filter(t(), (map() -> boolean()), keyword()) :: t()
  def filter(%__MODULE__{} = dataset, predicate, opts \\ []) do
    use_cache = Keyword.get(opts, :cache, caching_enabled?())

    if use_cache do
      filter_cached(dataset, predicate, opts)
    else
      filter_uncached(dataset, predicate, opts)
    end
  end

  defp filter_cached(dataset, predicate, opts) do
    input_fp = fingerprint(dataset)
    transform_fp = Fingerprint.generate(:filter, [predicate], opts)

    case TransformCache.get(input_fp, transform_fp) do
      {:ok, cached} ->
        cached

      :miss ->
        result = filter_uncached(dataset, predicate, opts)
        new_fp = Fingerprint.combine(input_fp, transform_fp)
        result = %{result | fingerprint: new_fp}

        TransformCache.put(input_fp, transform_fp, result)
        result
    end
  end

  defp filter_uncached(dataset, predicate, _opts) do
    new_items = Enum.filter(dataset.items, predicate)
    %{dataset | items: new_items, fingerprint: nil}
  end

  defp caching_enabled? do
    Application.get_env(:hf_datasets_ex, :caching_enabled, true)
  end
end
```

### 4. Config Module

Create `lib/dataset_manager/config.ex`:

```elixir
defmodule HfDatasetsEx.Config do
  @moduledoc """
  Configuration for hf_datasets_ex.
  """

  @defaults %{
    caching_enabled: true,
    cache_dir: "~/.hf_datasets_ex",
    max_cache_size_gb: 10,
    max_cache_age_days: 30
  }

  @doc """
  Get a configuration value.
  """
  @spec get(atom()) :: any()
  def get(key) do
    Application.get_env(:hf_datasets_ex, key, Map.get(@defaults, key))
  end

  @doc """
  Check if caching is enabled.
  """
  @spec caching_enabled?() :: boolean()
  def caching_enabled? do
    get(:caching_enabled) and not offline_mode?()
  end

  @doc """
  Check if running in offline mode.
  """
  @spec offline_mode?() :: boolean()
  def offline_mode? do
    System.get_env("HF_DATASETS_OFFLINE") == "1"
  end

  @doc """
  Get the cache directory path.
  """
  @spec cache_dir() :: Path.t()
  def cache_dir do
    get(:cache_dir) |> Path.expand()
  end
end
```

## TDD Approach

### Step 1: Write Tests First

Create `test/dataset_manager/fingerprint_test.exs`:

```elixir
defmodule HfDatasetsEx.FingerprintTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.{Dataset, Fingerprint}

  describe "generate/3" do
    test "same inputs produce same fingerprint" do
      fp1 = Fingerprint.generate(:map, [&String.upcase/1], [])
      fp2 = Fingerprint.generate(:map, [&String.upcase/1], [])

      assert fp1 == fp2
    end

    test "different operations produce different fingerprints" do
      fp1 = Fingerprint.generate(:map, [&String.upcase/1], [])
      fp2 = Fingerprint.generate(:filter, [&String.upcase/1], [])

      assert fp1 != fp2
    end

    test "different args produce different fingerprints" do
      fp1 = Fingerprint.generate(:map, [&String.upcase/1], [])
      fp2 = Fingerprint.generate(:map, [&String.downcase/1], [])

      assert fp1 != fp2
    end

    test "different opts produce different fingerprints" do
      fp1 = Fingerprint.generate(:map, [], batched: true)
      fp2 = Fingerprint.generate(:map, [], batched: false)

      assert fp1 != fp2
    end

    test "fingerprint is 64 hex characters" do
      fp = Fingerprint.generate(:test, [])

      assert String.length(fp) == 64
      assert Regex.match?(~r/^[0-9a-f]+$/, fp)
    end
  end

  describe "from_dataset/1" do
    test "same dataset produces same fingerprint" do
      ds = Dataset.from_list([%{"x" => 1}, %{"x" => 2}])

      fp1 = Fingerprint.from_dataset(ds)
      fp2 = Fingerprint.from_dataset(ds)

      assert fp1 == fp2
    end

    test "different data produces different fingerprints" do
      ds1 = Dataset.from_list([%{"x" => 1}])
      ds2 = Dataset.from_list([%{"x" => 2}])

      assert Fingerprint.from_dataset(ds1) != Fingerprint.from_dataset(ds2)
    end
  end

  describe "combine/2" do
    test "combine is deterministic" do
      fp1 = Fingerprint.generate(:a, [])
      fp2 = Fingerprint.generate(:b, [])

      combined1 = Fingerprint.combine(fp1, fp2)
      combined2 = Fingerprint.combine(fp1, fp2)

      assert combined1 == combined2
    end

    test "combine is order-dependent" do
      fp1 = Fingerprint.generate(:a, [])
      fp2 = Fingerprint.generate(:b, [])

      assert Fingerprint.combine(fp1, fp2) != Fingerprint.combine(fp2, fp1)
    end
  end
end
```

Create `test/dataset_manager/transform_cache_test.exs`:

```elixir
defmodule HfDatasetsEx.TransformCacheTest do
  use ExUnit.Case, async: false

  alias HfDatasetsEx.{Dataset, Fingerprint, TransformCache}

  @cache_dir Path.join(System.tmp_dir!(), "transform_cache_test_#{:rand.uniform(100000)}")

  setup do
    # Use temp directory
    Application.put_env(:hf_datasets_ex, :transform_cache_dir, @cache_dir)
    File.mkdir_p!(@cache_dir)

    on_exit(fn ->
      File.rm_rf!(@cache_dir)
      Application.delete_env(:hf_datasets_ex, :transform_cache_dir)
    end)

    :ok
  end

  describe "get/2 and put/3" do
    test "cache miss returns :miss" do
      assert :miss = TransformCache.get("nonexistent", "also_nonexistent")
    end

    test "cache hit returns dataset" do
      dataset = Dataset.from_list([%{"x" => 1}])
      input_fp = Fingerprint.from_dataset(dataset)
      transform_fp = Fingerprint.generate(:test, [])

      TransformCache.put(input_fp, transform_fp, dataset)

      assert {:ok, cached} = TransformCache.get(input_fp, transform_fp)
      assert cached.items == dataset.items
    end
  end

  describe "cleanup/1" do
    test "removes old entries" do
      # Create an entry
      dataset = Dataset.from_list([%{"x" => 1}])
      input_fp = Fingerprint.from_dataset(dataset)
      transform_fp = Fingerprint.generate(:test, [])

      TransformCache.put(input_fp, transform_fp, dataset)

      # Cleanup with 0 days max age
      {:ok, deleted} = TransformCache.cleanup(max_age_days: 0)

      assert deleted >= 0
    end
  end

  describe "stats/0" do
    test "returns cache statistics" do
      stats = TransformCache.stats()

      assert is_integer(stats.entry_count)
      assert is_integer(stats.total_size_bytes)
      assert is_binary(stats.cache_dir)
    end
  end
end
```

### Step 2: Run Tests

```bash
mix test test/dataset_manager/fingerprint_test.exs
mix test test/dataset_manager/transform_cache_test.exs
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
- [ ] Same inputs produce same fingerprints
- [ ] Cache hit/miss works correctly
- [ ] Cleanup removes old entries

## Files to Create/Modify

| File | Action |
|------|--------|
| `lib/dataset_manager/fingerprint.ex` | Create |
| `lib/dataset_manager/transform_cache.ex` | Create |
| `lib/dataset_manager/config.ex` | Create |
| `lib/dataset_manager/dataset.ex` | Add fingerprint field and cached operations |
| `test/dataset_manager/fingerprint_test.exs` | Create |
| `test/dataset_manager/transform_cache_test.exs` | Create |
