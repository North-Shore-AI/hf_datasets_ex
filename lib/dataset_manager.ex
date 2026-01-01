defmodule HfDatasetsEx do
  @moduledoc """
  HuggingFace Datasets for Elixir.

  A native Elixir port of the HuggingFace datasets library, providing:
  - Loading datasets from HuggingFace Hub
  - Streaming support for large datasets
  - Dataset operations (map, filter, shuffle, split)
  - Automatic caching and version tracking
  - Dataset sampling and splitting

  ## Quick Start

      # Load a dataset by repo_id
      {:ok, dataset} = HfDatasetsEx.load_dataset("openai/gsm8k", config: "main", split: "train")

      # Load all splits as DatasetDict
      {:ok, dd} = HfDatasetsEx.load_dataset("openai/gsm8k")
      train = dd["train"]

      # Streaming mode
      {:ok, stream} = HfDatasetsEx.load_dataset("openai/gsm8k", split: "train", streaming: true)

  ## Supported Datasets

  - `:mmlu` - Massive Multitask Language Understanding (all subjects)
  - `:mmlu_stem` - MMLU STEM subjects only
  - `:humaneval` - Code generation benchmark
  - `:gsm8k` - Grade school math problems
  - Any HuggingFace Hub dataset by repo_id

  ## Custom Datasets

  Load custom datasets from local files:

      {:ok, dataset} = HfDatasetsEx.load("my_dataset", source: "path/to/data.jsonl")
  """

  alias HfDatasetsEx.{Cache, Loader, Registry, Sampler}

  # Dataset loading

  @doc """
  Load a dataset by name.

  See `HfDatasetsEx.Loader.load/2` for full documentation.
  """
  defdelegate load(dataset_name, opts \\ []), to: Loader

  @doc """
  Load a HuggingFace dataset by repo_id.

  See `HfDatasetsEx.Loader.load_dataset/2` for full documentation.
  """
  defdelegate load_dataset(repo_id, opts \\ []), to: Loader

  # Sampling

  @doc """
  Create random sample from dataset.

  See `HfDatasetsEx.Sampler.random/2` for full documentation.
  """
  defdelegate random_sample(dataset, opts \\ []), to: Sampler, as: :random

  @doc """
  Create stratified sample from dataset.

  See `HfDatasetsEx.Sampler.stratified/2` for full documentation.
  """
  defdelegate stratified_sample(dataset, opts \\ []), to: Sampler, as: :stratified

  @doc """
  Create k-fold cross-validation splits.

  See `HfDatasetsEx.Sampler.k_fold/2` for full documentation.
  """
  defdelegate k_fold(dataset, opts \\ []), to: Sampler

  @doc """
  Split dataset into train and test sets.

  See `HfDatasetsEx.Sampler.train_test_split/2` for full documentation.
  """
  defdelegate train_test_split(dataset, opts \\ []), to: Sampler

  # Cache management

  @doc """
  List all cached datasets.

  See `HfDatasetsEx.Cache.list/0` for full documentation.
  """
  defdelegate list_cached(), to: Cache, as: :list

  @doc """
  Clear all cached datasets.

  See `HfDatasetsEx.Cache.clear_all/0` for full documentation.
  """
  defdelegate clear_cache(), to: Cache, as: :clear_all

  @doc """
  Invalidate cache for specific dataset.

  See `HfDatasetsEx.Loader.invalidate_cache/1` for full documentation.
  """
  defdelegate invalidate_cache(dataset_name), to: Loader

  # Registry

  @doc """
  List all available datasets.

  See `HfDatasetsEx.Registry.list_available/0` for full documentation.
  """
  defdelegate list_available(), to: Registry

  @doc """
  Get metadata for a dataset.

  See `HfDatasetsEx.Registry.get_metadata/1` for full documentation.
  """
  defdelegate get_metadata(dataset_name), to: Registry
end
