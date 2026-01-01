# Implementation Prompt: Dataset Builder Pattern

## Priority: P2 (Medium)

## Objective

Implement the `DatasetBuilder` behaviour and related infrastructure for defining custom datasets declaratively.

## Required Reading

Before starting, read these files completely:

```
lib/dataset_manager/loader.ex
lib/dataset_manager/loader/mmlu.ex
lib/dataset_manager/loader/gsm8k.ex
lib/dataset_manager/data_files.ex
lib/dataset_manager/cache.ex
docs/20251231/gap_analysis/07_builder_pattern.md
```

## Context

The Python `datasets` library uses a builder pattern:
- `DatasetBuilder` - Base class for dataset definitions
- `BuilderConfig` - Configuration for dataset variants
- `SplitGenerator` - Defines how to create splits
- `DownloadManager` - Handles file downloads/extraction

This enables:
- Declarative dataset definitions
- Automatic caching of downloads and builds
- Multiple configs per dataset (e.g., `mmlu-stem`, `mmlu-humanities`)
- Reusable download/extraction logic

The Elixir port uses direct loader functions which work but aren't as reusable.

## Implementation Requirements

### 1. BuilderConfig Struct

Create `lib/dataset_manager/builder_config.ex`:

```elixir
defmodule HfDatasetsEx.BuilderConfig do
  @moduledoc """
  Configuration for a dataset builder variant.

  ## Examples

      config = BuilderConfig.new(
        name: "stem",
        version: "1.0.0",
        description: "STEM subjects only"
      )

  """

  @type t :: %__MODULE__{
    name: String.t(),
    version: String.t(),
    description: String.t() | nil,
    data_dir: Path.t() | nil,
    data_files: map() | nil
  }

  @enforce_keys [:name]
  defstruct [
    :name,
    version: "1.0.0",
    description: nil,
    data_dir: nil,
    data_files: nil
  ]

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      name: Keyword.get(opts, :name, "default"),
      version: Keyword.get(opts, :version, "1.0.0"),
      description: Keyword.get(opts, :description),
      data_dir: Keyword.get(opts, :data_dir),
      data_files: Keyword.get(opts, :data_files)
    }
  end
end
```

### 2. SplitGenerator Struct

Create `lib/dataset_manager/split_generator.ex`:

```elixir
defmodule HfDatasetsEx.SplitGenerator do
  @moduledoc """
  Defines how to generate a dataset split.

  ## Examples

      # From file path
      SplitGenerator.new(:train, "/path/to/train.jsonl")

      # From generator kwargs
      SplitGenerator.new(:test, %{data_dir: "/data", pattern: "*.json"})

  """

  @type t :: %__MODULE__{
    name: atom(),
    gen_kwargs: map()
  }

  @enforce_keys [:name, :gen_kwargs]
  defstruct [:name, :gen_kwargs]

  @spec new(atom(), map() | Path.t()) :: t()
  def new(split_name, filepath) when is_binary(filepath) do
    %__MODULE__{name: split_name, gen_kwargs: %{filepath: filepath}}
  end

  def new(split_name, gen_kwargs) when is_map(gen_kwargs) do
    %__MODULE__{name: split_name, gen_kwargs: gen_kwargs}
  end
end
```

### 3. DatasetInfo Struct

Create `lib/dataset_manager/dataset_info.ex`:

```elixir
defmodule HfDatasetsEx.DatasetInfo do
  @moduledoc """
  Metadata about a dataset.
  """

  alias HfDatasetsEx.Features

  @type t :: %__MODULE__{
    description: String.t() | nil,
    citation: String.t() | nil,
    homepage: String.t() | nil,
    license: String.t() | nil,
    features: Features.t() | nil,
    supervised_keys: {String.t(), String.t()} | nil,
    builder_name: String.t() | nil,
    config_name: String.t() | nil,
    version: String.t() | nil,
    splits: map() | nil,
    download_size: non_neg_integer() | nil,
    dataset_size: non_neg_integer() | nil
  }

  defstruct [
    :description,
    :citation,
    :homepage,
    :license,
    :features,
    :supervised_keys,
    :builder_name,
    :config_name,
    :version,
    :splits,
    :download_size,
    :dataset_size
  ]

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end
end
```

### 4. DownloadManager Module

Create `lib/dataset_manager/download_manager.ex`:

```elixir
defmodule HfDatasetsEx.DownloadManager do
  @moduledoc """
  Manages file downloads and extraction for dataset builders.
  """

  @type t :: %__MODULE__{
    cache_dir: Path.t(),
    download_config: map()
  }

  defstruct [:cache_dir, :download_config]

  @default_cache_dir Path.expand("~/.hf_datasets_ex/downloads")

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      cache_dir: Keyword.get(opts, :cache_dir, @default_cache_dir),
      download_config: Keyword.get(opts, :download_config, %{})
    }
  end

  @doc """
  Download a file and return its local path.

  Caches downloads by URL hash.
  """
  @spec download(t(), String.t()) :: {:ok, Path.t()} | {:error, term()}
  def download(%__MODULE__{cache_dir: cache_dir}, url) do
    cache_path = url_to_cache_path(cache_dir, url)

    if File.exists?(cache_path) do
      {:ok, cache_path}
    else
      File.mkdir_p!(Path.dirname(cache_path))
      do_download(url, cache_path)
    end
  end

  @doc """
  Download and extract an archive.

  Returns path to extracted directory.
  """
  @spec download_and_extract(t(), String.t()) :: {:ok, Path.t()} | {:error, term()}
  def download_and_extract(%__MODULE__{} = dm, url) do
    with {:ok, archive_path} <- download(dm, url) do
      extract_dir = archive_path <> "_extracted"

      if File.exists?(extract_dir) do
        {:ok, extract_dir}
      else
        extract(archive_path, extract_dir)
      end
    end
  end

  @doc """
  Download multiple files in parallel.
  """
  @spec download_many(t(), [String.t()]) :: {:ok, [Path.t()]} | {:error, term()}
  def download_many(%__MODULE__{} = dm, urls) do
    results =
      urls
      |> Task.async_stream(&download(dm, &1), max_concurrency: 8, timeout: 120_000)
      |> Enum.map(fn
        {:ok, {:ok, path}} -> {:ok, path}
        {:ok, {:error, e}} -> {:error, e}
        {:exit, reason} -> {:error, {:exit, reason}}
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      {:ok, Enum.map(results, fn {:ok, path} -> path end)}
    else
      {:error, {:download_failed, errors}}
    end
  end

  defp url_to_cache_path(cache_dir, url) do
    hash = :crypto.hash(:sha256, url) |> Base.encode16(case: :lower) |> String.slice(0, 16)
    ext = url |> URI.parse() |> Map.get(:path, "") |> Path.extname()

    Path.join(cache_dir, "#{hash}#{ext}")
  end

  defp do_download(url, dest_path) do
    # Use httpc or Req
    case :httpc.request(:get, {to_charlist(url), []}, [], body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        File.write!(dest_path, body)
        {:ok, dest_path}

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract(archive_path, extract_dir) do
    File.mkdir_p!(extract_dir)

    result = cond do
      String.ends_with?(archive_path, ".tar.gz") or String.ends_with?(archive_path, ".tgz") ->
        :erl_tar.extract(to_charlist(archive_path), [:compressed, {:cwd, to_charlist(extract_dir)}])

      String.ends_with?(archive_path, ".zip") ->
        :zip.unzip(to_charlist(archive_path), [{:cwd, to_charlist(extract_dir)}])

      String.ends_with?(archive_path, ".gz") ->
        content = archive_path |> File.read!() |> :zlib.gunzip()
        output = Path.join(extract_dir, Path.basename(archive_path, ".gz"))
        File.write!(output, content)
        :ok

      true ->
        {:error, {:unknown_archive_type, archive_path}}
    end

    case result do
      :ok -> {:ok, extract_dir}
      {:ok, _} -> {:ok, extract_dir}
      error -> error
    end
  end
end
```

### 5. DatasetBuilder Behaviour

Create `lib/dataset_manager/dataset_builder.ex`:

```elixir
defmodule HfDatasetsEx.DatasetBuilder do
  @moduledoc """
  Behaviour for defining custom dataset builders.

  ## Usage

      defmodule MyDataset do
        use HfDatasetsEx.DatasetBuilder

        @impl true
        def info do
          DatasetInfo.new(
            description: "My custom dataset",
            features: Features.new(%{
              "text" => %Value{dtype: :string},
              "label" => %ClassLabel{names: ["neg", "pos"]}
            })
          )
        end

        @impl true
        def split_generators(dl_manager, _config) do
          {:ok, train_path} = DownloadManager.download(dl_manager, @train_url)
          {:ok, test_path} = DownloadManager.download(dl_manager, @test_url)

          [
            SplitGenerator.new(:train, train_path),
            SplitGenerator.new(:test, test_path)
          ]
        end

        @impl true
        def generate_examples(filepath, _split) do
          filepath
          |> File.stream!()
          |> Stream.with_index()
          |> Stream.map(fn {line, idx} -> {idx, Jason.decode!(line)} end)
        end
      end

  """

  alias HfDatasetsEx.{BuilderConfig, DatasetInfo, DownloadManager, SplitGenerator}

  @callback info() :: DatasetInfo.t()
  @callback configs() :: [BuilderConfig.t()]
  @callback default_config_name() :: String.t() | nil
  @callback split_generators(DownloadManager.t(), BuilderConfig.t()) :: [SplitGenerator.t()]
  @callback generate_examples(map(), atom()) :: Enumerable.t()

  @optional_callbacks [configs: 0, default_config_name: 0]

  defmacro __using__(_opts) do
    quote do
      @behaviour HfDatasetsEx.DatasetBuilder

      alias HfDatasetsEx.{
        BuilderConfig,
        DatasetInfo,
        DownloadManager,
        SplitGenerator,
        Features
      }

      alias HfDatasetsEx.Features.{Value, ClassLabel, Sequence}

      @impl true
      def configs, do: [BuilderConfig.new()]

      @impl true
      def default_config_name, do: nil

      defoverridable [configs: 0, default_config_name: 0]
    end
  end
end
```

### 6. Builder Runner

Create `lib/dataset_manager/builder.ex`:

```elixir
defmodule HfDatasetsEx.Builder do
  @moduledoc """
  Runs a dataset builder to produce a Dataset or DatasetDict.
  """

  alias HfDatasetsEx.{
    Dataset,
    DatasetDict,
    BuilderConfig,
    DownloadManager,
    SplitGenerator
  }

  @type build_opts :: [
    config_name: String.t() | nil,
    split: String.t() | atom() | nil,
    cache_dir: Path.t() | nil
  ]

  @doc """
  Build a dataset using a builder module.

  ## Options

    * `:config_name` - Config to use (default: first or default_config_name)
    * `:split` - Specific split to build (default: all)
    * `:cache_dir` - Cache directory for downloads

  ## Examples

      {:ok, dataset_dict} = Builder.build(MyDataset)
      {:ok, train} = Builder.build(MyDataset, split: :train)

  """
  @spec build(module(), build_opts()) :: {:ok, DatasetDict.t() | Dataset.t()} | {:error, term()}
  def build(builder_module, opts \\ []) do
    config_name = Keyword.get(opts, :config_name)
    requested_split = Keyword.get(opts, :split)
    cache_dir = Keyword.get(opts, :cache_dir)

    with {:ok, config} <- get_config(builder_module, config_name),
         dm = DownloadManager.new(cache_dir: cache_dir),
         split_gens = builder_module.split_generators(dm, config),
         {:ok, splits} <- generate_splits(builder_module, split_gens, requested_split) do

      info = builder_module.info()

      datasets =
        Map.new(splits, fn {split_name, items} ->
          dataset = %Dataset{
            name: "#{builder_module}:#{config.name}",
            version: config.version,
            items: items,
            features: info.features,
            metadata: %{
              description: info.description,
              citation: info.citation,
              license: info.license,
              builder: builder_module,
              config: config.name
            }
          }
          {to_string(split_name), dataset}
        end)

      result = if requested_split do
        # Return single dataset
        Map.values(datasets) |> hd()
      else
        # Return DatasetDict
        DatasetDict.new(datasets)
      end

      {:ok, result}
    end
  end

  defp get_config(builder_module, nil) do
    configs = builder_module.configs()
    default_name = builder_module.default_config_name()

    config =
      if default_name do
        Enum.find(configs, hd(configs), &(&1.name == default_name))
      else
        hd(configs)
      end

    {:ok, config}
  end

  defp get_config(builder_module, config_name) do
    configs = builder_module.configs()

    case Enum.find(configs, &(&1.name == config_name)) do
      nil ->
        available = Enum.map(configs, & &1.name)
        {:error, {:unknown_config, config_name, available}}
      config ->
        {:ok, config}
    end
  end

  defp generate_splits(builder_module, split_gens, requested_split) do
    split_gens =
      if requested_split do
        split_atom = if is_binary(requested_split), do: String.to_atom(requested_split), else: requested_split
        Enum.filter(split_gens, &(&1.name == split_atom))
      else
        split_gens
      end

    if split_gens == [] do
      {:error, :no_splits_found}
    else
      results =
        Enum.map(split_gens, fn %SplitGenerator{name: name, gen_kwargs: kwargs} ->
          items =
            builder_module.generate_examples(kwargs, name)
            |> Enum.map(fn
              {_idx, item} -> item
              item when is_map(item) -> item
            end)

          {name, items}
        end)

      {:ok, results}
    end
  end
end
```

## TDD Approach

### Step 1: Write Tests First

Create `test/dataset_manager/builder_test.exs`:

```elixir
defmodule HfDatasetsEx.BuilderTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.{Builder, Dataset, DatasetDict, DatasetInfo, Features}
  alias HfDatasetsEx.Features.Value

  # Test builder module
  defmodule TestDataset do
    use HfDatasetsEx.DatasetBuilder

    @impl true
    def info do
      DatasetInfo.new(
        description: "Test dataset",
        features: Features.new(%{"x" => %Value{dtype: :int32}})
      )
    end

    @impl true
    def split_generators(_dm, _config) do
      [
        SplitGenerator.new(:train, %{data: [1, 2, 3]}),
        SplitGenerator.new(:test, %{data: [4, 5]})
      ]
    end

    @impl true
    def generate_examples(%{data: data}, _split) do
      data
      |> Enum.with_index()
      |> Enum.map(fn {x, idx} -> {idx, %{"x" => x}} end)
    end
  end

  defmodule MultiConfigDataset do
    use HfDatasetsEx.DatasetBuilder

    @impl true
    def info, do: DatasetInfo.new()

    @impl true
    def configs do
      [
        BuilderConfig.new(name: "small"),
        BuilderConfig.new(name: "large")
      ]
    end

    @impl true
    def default_config_name, do: "small"

    @impl true
    def split_generators(_dm, %{name: "small"}) do
      [SplitGenerator.new(:train, %{data: [1, 2]})]
    end

    def split_generators(_dm, %{name: "large"}) do
      [SplitGenerator.new(:train, %{data: [1, 2, 3, 4, 5]})]
    end

    @impl true
    def generate_examples(%{data: data}, _split) do
      Enum.map(data, &%{"x" => &1})
    end
  end

  describe "Builder.build/2" do
    test "builds DatasetDict with all splits" do
      assert {:ok, %DatasetDict{} = dd} = Builder.build(TestDataset)

      assert DatasetDict.split_names(dd) == ["test", "train"]
      assert Dataset.num_items(dd.datasets["train"]) == 3
      assert Dataset.num_items(dd.datasets["test"]) == 2
    end

    test "builds single split when specified" do
      assert {:ok, %Dataset{} = ds} = Builder.build(TestDataset, split: :train)

      assert Dataset.num_items(ds) == 3
    end

    test "uses default config" do
      assert {:ok, %DatasetDict{} = dd} = Builder.build(MultiConfigDataset)

      train = dd.datasets["train"]
      assert Dataset.num_items(train) == 2  # "small" config
    end

    test "uses specified config" do
      assert {:ok, %DatasetDict{} = dd} = Builder.build(MultiConfigDataset, config_name: "large")

      train = dd.datasets["train"]
      assert Dataset.num_items(train) == 5  # "large" config
    end

    test "returns error for unknown config" do
      assert {:error, {:unknown_config, "nonexistent", _}} =
        Builder.build(MultiConfigDataset, config_name: "nonexistent")
    end

    test "preserves info in dataset" do
      {:ok, dd} = Builder.build(TestDataset)

      train = dd.datasets["train"]
      assert train.features != nil
      assert train.metadata.description == "Test dataset"
    end
  end
end

defmodule HfDatasetsEx.DownloadManagerTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.DownloadManager

  @temp_dir Path.join(System.tmp_dir!(), "dm_test_#{:rand.uniform(100000)}")

  setup do
    File.mkdir_p!(@temp_dir)
    on_exit(fn -> File.rm_rf!(@temp_dir) end)
    {:ok, dm: DownloadManager.new(cache_dir: @temp_dir)}
  end

  describe "download/2" do
    @tag :network
    test "downloads file", %{dm: dm} do
      # Use a small known file
      url = "https://raw.githubusercontent.com/huggingface/datasets/main/README.md"

      assert {:ok, path} = DownloadManager.download(dm, url)
      assert File.exists?(path)
    end

    test "caches downloads", %{dm: dm} do
      # Create a fake cached file
      hash = :crypto.hash(:sha256, "http://example.com/file.txt")
             |> Base.encode16(case: :lower)
             |> String.slice(0, 16)
      cache_path = Path.join(@temp_dir, "#{hash}.txt")
      File.write!(cache_path, "cached content")

      assert {:ok, ^cache_path} = DownloadManager.download(dm, "http://example.com/file.txt")
    end
  end

  describe "download_and_extract/2" do
    test "extracts tar.gz", %{dm: dm} do
      # Create test archive
      archive_path = Path.join(@temp_dir, "test.tar.gz")
      extract_dir = archive_path <> "_extracted"

      # Create simple tar.gz
      File.mkdir_p!(Path.join(@temp_dir, "test_content"))
      File.write!(Path.join(@temp_dir, "test_content/file.txt"), "hello")

      System.cmd("tar", ["-czf", archive_path, "-C", @temp_dir, "test_content"])

      # Mock the download by creating the cached file
      hash = :crypto.hash(:sha256, "http://example.com/test.tar.gz")
             |> Base.encode16(case: :lower)
             |> String.slice(0, 16)
      cached_path = Path.join(@temp_dir, "#{hash}.tar.gz")
      File.copy!(archive_path, cached_path)

      assert {:ok, dir} = DownloadManager.download_and_extract(dm, "http://example.com/test.tar.gz")
      assert File.exists?(Path.join(dir, "test_content/file.txt"))
    end
  end
end
```

### Step 2: Run Tests

```bash
mix test test/dataset_manager/builder_test.exs
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
- [ ] Builders produce correct DatasetDict
- [ ] Config selection works
- [ ] Downloads are cached

## Files to Create

| File | Action |
|------|--------|
| `lib/dataset_manager/builder.ex` | Create |
| `lib/dataset_manager/builder_config.ex` | Create |
| `lib/dataset_manager/dataset_builder.ex` | Create |
| `lib/dataset_manager/dataset_info.ex` | Create |
| `lib/dataset_manager/split_generator.ex` | Create |
| `lib/dataset_manager/download_manager.ex` | Create |
| `test/dataset_manager/builder_test.exs` | Create |
