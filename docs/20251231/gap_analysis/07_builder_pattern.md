# Gap Analysis: Builder Pattern

## Overview

The Python `datasets` library uses a builder pattern (`DatasetBuilder`, `BuilderConfig`) for defining custom datasets. This enables:
- Declarative dataset definition
- Automatic download/extraction
- Split generation
- Caching of build process

The Elixir port uses direct loader functions without a formal builder pattern.

## Python Builder Architecture

```python
# datasets/builder.py
class BuilderConfig:
    name: str
    version: Version
    data_dir: str | None
    data_files: dict | None
    description: str | None

class DatasetBuilder:
    BUILDER_CONFIG_CLASS = BuilderConfig
    BUILDER_CONFIGS: list[BuilderConfig] = []
    DEFAULT_CONFIG_NAME: str | None = None

    def __init__(self, config_name=None, ...):
        self.config = self._create_config(config_name)

    @abstractmethod
    def _info(self) -> DatasetInfo:
        """Define dataset metadata and features."""
        pass

    @abstractmethod
    def _split_generators(self, dl_manager) -> list[SplitGenerator]:
        """Define how to download and split data."""
        pass

    @abstractmethod
    def _generate_examples(self, filepath, split) -> Iterator[tuple[int, dict]]:
        """Generate individual examples from downloaded files."""
        pass

    def download_and_prepare(self):
        """Download data and prepare cache."""
        pass

    def as_dataset(self, split=None) -> Dataset | DatasetDict:
        """Return prepared dataset."""
        pass
```

## Proposed Elixir Builder Pattern

### BuilderConfig

```elixir
defmodule HfDatasetsEx.BuilderConfig do
  @type t :: %__MODULE__{
    name: String.t(),
    version: String.t(),
    data_dir: Path.t() | nil,
    data_files: map() | nil,
    description: String.t() | nil
  }

  defstruct [
    :name,
    :version,
    :data_dir,
    :data_files,
    :description
  ]

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      name: Keyword.get(opts, :name, "default"),
      version: Keyword.get(opts, :version, "1.0.0"),
      data_dir: Keyword.get(opts, :data_dir),
      data_files: Keyword.get(opts, :data_files),
      description: Keyword.get(opts, :description)
    }
  end
end
```

### DatasetBuilder Behaviour

```elixir
defmodule HfDatasetsEx.DatasetBuilder do
  @moduledoc """
  Behaviour for defining custom dataset builders.

  ## Example

      defmodule MyDataset do
        use HfDatasetsEx.DatasetBuilder

        @impl true
        def info do
          %DatasetInfo{
            description: "My custom dataset",
            features: Features.new(%{
              "text" => %Value{dtype: :string},
              "label" => %ClassLabel{names: ["neg", "pos"]}
            })
          }
        end

        @impl true
        def configs do
          [
            BuilderConfig.new(name: "v1", version: "1.0.0"),
            BuilderConfig.new(name: "v2", version: "2.0.0")
          ]
        end

        @impl true
        def split_generators(dl_manager, config) do
          train_path = dl_manager.download("https://example.com/train.jsonl")
          test_path = dl_manager.download("https://example.com/test.jsonl")

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
          |> Stream.map(fn {line, idx} ->
            {idx, Jason.decode!(line)}
          end)
        end
      end
  """

  alias HfDatasetsEx.{BuilderConfig, DatasetInfo, SplitGenerator, DownloadManager}

  @callback info() :: DatasetInfo.t()
  @callback configs() :: [BuilderConfig.t()]
  @callback default_config_name() :: String.t() | nil
  @callback split_generators(DownloadManager.t(), BuilderConfig.t()) :: [SplitGenerator.t()]
  @callback generate_examples(Path.t(), atom()) :: Enumerable.t()

  @optional_callbacks [configs: 0, default_config_name: 0]

  defmacro __using__(_opts) do
    quote do
      @behaviour HfDatasetsEx.DatasetBuilder

      import HfDatasetsEx.DatasetBuilder

      @impl true
      def configs, do: [HfDatasetsEx.BuilderConfig.new()]

      @impl true
      def default_config_name, do: nil

      defoverridable [configs: 0, default_config_name: 0]
    end
  end
end
```

### SplitGenerator

```elixir
defmodule HfDatasetsEx.SplitGenerator do
  @type t :: %__MODULE__{
    name: atom(),
    gen_kwargs: map()
  }

  defstruct [:name, :gen_kwargs]

  @spec new(atom(), map() | Path.t()) :: t()
  def new(split_name, gen_kwargs) when is_map(gen_kwargs) do
    %__MODULE__{name: split_name, gen_kwargs: gen_kwargs}
  end

  def new(split_name, filepath) when is_binary(filepath) do
    %__MODULE__{name: split_name, gen_kwargs: %{filepath: filepath}}
  end
end
```

### DownloadManager

```elixir
defmodule HfDatasetsEx.DownloadManager do
  @type t :: %__MODULE__{
    cache_dir: Path.t(),
    download_config: map()
  }

  defstruct [:cache_dir, :download_config]

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      cache_dir: Keyword.get(opts, :cache_dir, default_cache_dir()),
      download_config: Keyword.get(opts, :download_config, %{})
    }
  end

  @doc """
  Download a file and return its local path.
  """
  @spec download(t(), String.t()) :: Path.t()
  def download(%__MODULE__{} = dm, url) do
    cache_path = url_to_cache_path(dm.cache_dir, url)

    if File.exists?(cache_path) do
      cache_path
    else
      {:ok, content} = fetch_url(url)
      File.mkdir_p!(Path.dirname(cache_path))
      File.write!(cache_path, content)
      cache_path
    end
  end

  @doc """
  Download and extract an archive.
  """
  @spec download_and_extract(t(), String.t()) :: Path.t()
  def download_and_extract(%__MODULE__{} = dm, url) do
    archive_path = download(dm, url)
    extract_dir = archive_path <> "_extracted"

    if File.exists?(extract_dir) do
      extract_dir
    else
      extract(archive_path, extract_dir)
      extract_dir
    end
  end

  @doc """
  Download multiple files in parallel.
  """
  @spec download_many(t(), [String.t()]) :: [Path.t()]
  def download_many(%__MODULE__{} = dm, urls) do
    urls
    |> Task.async_stream(&download(dm, &1), max_concurrency: 8, timeout: 60_000)
    |> Enum.map(fn {:ok, path} -> path end)
  end

  defp extract(archive_path, extract_dir) do
    File.mkdir_p!(extract_dir)

    cond do
      String.ends_with?(archive_path, ".tar.gz") or String.ends_with?(archive_path, ".tgz") ->
        :erl_tar.extract(archive_path, [:compressed, {:cwd, extract_dir}])

      String.ends_with?(archive_path, ".zip") ->
        :zip.unzip(to_charlist(archive_path), [{:cwd, to_charlist(extract_dir)}])

      String.ends_with?(archive_path, ".gz") ->
        content = archive_path |> File.read!() |> :zlib.gunzip()
        output_path = Path.join(extract_dir, Path.basename(archive_path, ".gz"))
        File.write!(output_path, content)

      true ->
        raise "Unknown archive format: #{archive_path}"
    end
  end
end
```

### Builder Runner

```elixir
defmodule HfDatasetsEx.Builder do
  @moduledoc """
  Run a dataset builder to produce a Dataset or DatasetDict.
  """

  alias HfDatasetsEx.{Dataset, DatasetDict, DownloadManager, SplitGenerator}

  @spec build(module(), keyword()) :: {:ok, DatasetDict.t()} | {:error, term()}
  def build(builder_module, opts \\ []) do
    config_name = Keyword.get(opts, :config_name)
    split = Keyword.get(opts, :split)
    cache_dir = Keyword.get(opts, :cache_dir)

    with {:ok, config} <- get_config(builder_module, config_name),
         dm = DownloadManager.new(cache_dir: cache_dir),
         split_gens = builder_module.split_generators(dm, config),
         {:ok, splits} <- generate_splits(builder_module, split_gens, split) do

      info = builder_module.info()

      datasets =
        Map.new(splits, fn {split_name, items} ->
          dataset = %Dataset{
            name: config.name,
            version: config.version,
            items: items,
            features: info.features,
            metadata: %{
              description: info.description,
              citation: info.citation,
              license: info.license
            }
          }
          {to_string(split_name), dataset}
        end)

      {:ok, DatasetDict.new(datasets)}
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
      nil -> {:error, {:unknown_config, config_name, Enum.map(configs, & &1.name)}}
      config -> {:ok, config}
    end
  end

  defp generate_splits(builder_module, split_gens, requested_split) do
    split_gens =
      if requested_split do
        Enum.filter(split_gens, &(&1.name == requested_split or to_string(&1.name) == requested_split))
      else
        split_gens
      end

    results =
      Enum.map(split_gens, fn %SplitGenerator{name: name, gen_kwargs: kwargs} ->
        filepath = Map.get(kwargs, :filepath)

        items =
          builder_module.generate_examples(filepath, name)
          |> Enum.map(fn {_idx, item} -> item end)

        {name, items}
      end)

    {:ok, results}
  end
end
```

### DatasetInfo

```elixir
defmodule HfDatasetsEx.DatasetInfo do
  @type t :: %__MODULE__{
    description: String.t() | nil,
    citation: String.t() | nil,
    homepage: String.t() | nil,
    license: String.t() | nil,
    features: HfDatasetsEx.Features.t() | nil,
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
end
```

## Example Custom Builder

```elixir
defmodule HfDatasetsEx.Builders.IMDb do
  @moduledoc """
  IMDb movie review sentiment dataset.
  """

  use HfDatasetsEx.DatasetBuilder

  alias HfDatasetsEx.{DatasetInfo, Features, BuilderConfig, SplitGenerator}
  alias HfDatasetsEx.Features.{Value, ClassLabel}

  @url "https://ai.stanford.edu/~amaas/data/sentiment/aclImdb_v1.tar.gz"

  @impl true
  def info do
    %DatasetInfo{
      description: "Large Movie Review Dataset for binary sentiment classification.",
      citation: "@InProceedings{maas-EtAl:2011:ACL-HLT2011, ...}",
      homepage: "http://ai.stanford.edu/~amaas/data/sentiment/",
      license: "For research purposes only",
      features: Features.new(%{
        "text" => %Value{dtype: :string},
        "label" => %ClassLabel{names: ["neg", "pos"]}
      })
    }
  end

  @impl true
  def configs do
    [BuilderConfig.new(name: "plain_text", version: "1.0.0")]
  end

  @impl true
  def split_generators(dl_manager, _config) do
    data_dir = DownloadManager.download_and_extract(dl_manager, @url)

    [
      SplitGenerator.new(:train, %{data_dir: Path.join(data_dir, "aclImdb/train")}),
      SplitGenerator.new(:test, %{data_dir: Path.join(data_dir, "aclImdb/test")})
    ]
  end

  @impl true
  def generate_examples(_filepath, _split) do
    data_dir = _filepath.data_dir

    labels = ["neg", "pos"]

    labels
    |> Stream.flat_map(fn label ->
      label_dir = Path.join(data_dir, label)

      label_dir
      |> File.ls!()
      |> Stream.filter(&String.ends_with?(&1, ".txt"))
      |> Stream.map(fn filename ->
        path = Path.join(label_dir, filename)
        text = File.read!(path)
        id = Path.basename(filename, ".txt")

        {id, %{"text" => text, "label" => label}}
      end)
    end)
  end
end
```

## Integration with Existing Loaders

The builder pattern can coexist with existing loaders:

```elixir
defmodule HfDatasetsEx.Loader do
  @doc """
  Load dataset, using builder if available.
  """
  def load(name, opts \\ []) do
    cond do
      # Check if it's a registered builder
      builder = get_builder(name) ->
        Builder.build(builder, opts)

      # Check if it's a HuggingFace Hub dataset
      hub_dataset?(name) ->
        load_from_hub(name, opts)

      # Check if it's a local file
      File.exists?(name) ->
        load_from_file(name, opts)

      true ->
        {:error, {:unknown_dataset, name}}
    end
  end

  defp get_builder(name) do
    @builders[name]
  end
end
```

## Files to Create

| File | Purpose |
|------|---------|
| `lib/dataset_manager/builder.ex` | Builder runner |
| `lib/dataset_manager/builder_config.ex` | BuilderConfig struct |
| `lib/dataset_manager/dataset_builder.ex` | DatasetBuilder behaviour |
| `lib/dataset_manager/dataset_info.ex` | DatasetInfo struct |
| `lib/dataset_manager/split_generator.ex` | SplitGenerator struct |
| `lib/dataset_manager/download_manager.ex` | Download/extraction utilities |
| `lib/dataset_manager/builders/` | Directory for built-in builders |
| `test/dataset_manager/builder_test.exs` | Builder tests |

## Testing Requirements

```elixir
defmodule HfDatasetsEx.BuilderTest do
  use ExUnit.Case

  defmodule TestBuilder do
    use HfDatasetsEx.DatasetBuilder

    @impl true
    def info do
      %DatasetInfo{
        features: Features.new(%{"x" => %Value{dtype: :int32}})
      }
    end

    @impl true
    def split_generators(_dm, _config) do
      [SplitGenerator.new(:train, %{data: [1, 2, 3]})]
    end

    @impl true
    def generate_examples(_filepath, _split) do
      [1, 2, 3]
      |> Stream.with_index()
      |> Stream.map(fn {x, idx} -> {idx, %{"x" => x}} end)
    end
  end

  test "build produces DatasetDict" do
    {:ok, dd} = Builder.build(TestBuilder)

    assert DatasetDict.split_names(dd) == ["train"]
    assert Dataset.num_items(dd["train"]) == 3
  end
end
```

## Dependencies

No new dependencies required.
