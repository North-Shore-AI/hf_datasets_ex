<div align="center">
  <img src="assets/hf_datasets_ex.svg" alt="HfDatasetsEx Logo" width="200">
</div>

# HfDatasetsEx

[![Elixir](https://img.shields.io/badge/elixir-1.14+-purple.svg)](https://elixir-lang.org)
[![Hex.pm](https://img.shields.io/hexpm/v/hf_datasets_ex.svg)](https://hex.pm/packages/hf_datasets_ex)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-purple.svg)](https://hexdocs.pm/hf_datasets_ex)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/North-Shore-AI/hf_datasets_ex/blob/main/LICENSE)

**HuggingFace Datasets for Elixir** - A native Elixir port of the popular HuggingFace `datasets` library.

Load, stream, and process ML datasets from the HuggingFace Hub with full BEAM/OTP integration. Supports Parquet streaming, dataset splitting, shuffling, and seamless integration with Nx tensors for machine learning workflows.

## Features

- **HuggingFace Parity API**: `load_dataset` with repo_id/config/split/streaming
- **DatasetDict + IterableDataset**: Split indexing + streaming iteration
- **Streaming Support**: JSONL line-by-line; Parquet batch streaming
- **Features Schema**: Value/ClassLabel/Sequence/Image/Array2D-5D/Translation + inference
- **Image Decode**: Vix/libvips integration for vision datasets
- **Automatic Caching**: Fast access with local caching and version tracking
- **Transform Caching**: Fingerprint-based caching for map/filter operations
- **Dataset Operations**: map, filter, shuffle, select, take, skip, batch, concat, split, cast
- **Export Formats**: CSV, JSON, JSONL, Parquet, Arrow IPC, plain text
- **Hub Integration**: Push datasets directly to HuggingFace Hub
- **Nx Integration**: Format datasets as Nx tensors for ML workflows
- **Vector Search**: Built-in similarity search with cosine/L2/inner-product metrics
- **NumPy-Compatible Shuffling**: PCG64 PRNG matches Python's `datasets.shuffle(seed=N)` exactly
- **Reproducibility**: Deterministic sampling with seeds, version tracking
- **Custom Builders**: Define custom dataset builders with the DatasetBuilder behaviour
- **Extensible**: Easy integration of custom datasets and sources

## Installation

Add `hf_datasets_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hf_datasets_ex, "~> 0.1.2"}
  ]
end
```

### System Dependencies

Image decoding uses `vix` (libvips). Install libvips if you plan to use vision datasets:

```bash
# macOS
brew install vips

# Ubuntu/Debian
apt-get install libvips-dev
```

## Quick Start

```elixir
# Load a dataset by repo_id
{:ok, dataset} = HfDatasetsEx.load_dataset("openai/gsm8k", config: "main", split: "train")

# Access items
Enum.take(dataset, 5)

# Load all splits (returns DatasetDict)
{:ok, dd} = HfDatasetsEx.load_dataset("openai/gsm8k")
train = dd["train"]
test = dd["test"]

# Streaming mode (memory efficient)
{:ok, stream} = HfDatasetsEx.load_dataset("openai/gsm8k",
  split: "train",
  streaming: true
)

# Process lazily
stream
|> HfDatasetsEx.IterableDataset.filter(fn item -> String.length(item["question"]) > 100 end)
|> HfDatasetsEx.IterableDataset.take(100)
|> Enum.to_list()
```

## Supported Datasets

### Core Benchmarks

| Category | Datasets |
|----------|----------|
| **Math** | GSM8K, MATH-500, Hendrycks MATH, DeepMath, POLARIS |
| **Chat/Instruction** | Tulu-3-SFT, No Robots |
| **Preference/DPO** | HH-RLHF, HelpSteer2, HelpSteer3, UltraFeedback, Arena-140K, Tulu-3-Preference |
| **Code** | HumanEval, DeepCoder |
| **Reasoning** | OpenThoughts3, DeepMath reasoning |
| **Knowledge** | MMLU (57 subjects across STEM, humanities, social sciences) |
| **Vision** | Caltech101, Oxford Flowers 102, Oxford-IIIT Pet, Stanford Cars |

`load_dataset/2` works with **any public HuggingFace dataset repo_id**.

## Usage Examples

### Loading Datasets

```elixir
# Load by HuggingFace repo_id
{:ok, gsm8k} = HfDatasetsEx.load_dataset("openai/gsm8k",
  config: "main",
  split: "train"
)

# Load all splits (DatasetDict)
{:ok, dd} = HfDatasetsEx.load_dataset("openai/gsm8k")
train = dd["train"]

# Streaming (IterableDataset)
{:ok, stream} = HfDatasetsEx.load_dataset("openai/gsm8k",
  split: "train",
  streaming: true
)

# Vision datasets
{:ok, caltech} = HfDatasetsEx.Loader.Vision.load(:caltech101, sample_size: 5)
```

### Dataset Operations

```elixir
alias HfDatasetsEx.Dataset

# Transform items
mapped = Dataset.map(dataset, fn item ->
  Map.put(item, :processed, true)
end)

# Filter items
filtered = Dataset.filter(dataset, fn item ->
  item.difficulty == "hard"
end)

# Shuffle with seed (uses NumPy-compatible PCG64 by default)
shuffled = Dataset.shuffle(dataset, seed: 42)

# Use Erlang's PRNG instead (faster, but different order than Python)
shuffled_erlang = Dataset.shuffle(dataset, seed: 42, generator: :erlang)

# Select columns
selected = Dataset.select(dataset, ["question", "answer"])

# Pagination
page = dataset |> Dataset.skip(100) |> Dataset.take(10)

# Batch processing
batches = Dataset.batch(dataset, 32)

# Train/test split
{train, test} = Dataset.split(dataset, test_size: 0.2, seed: 42)

# Concatenate datasets
combined = Dataset.concat([dataset1, dataset2, dataset3])
```

### Streaming with IterableDataset

```elixir
alias HfDatasetsEx.IterableDataset

{:ok, stream} = HfDatasetsEx.load_dataset("big-dataset/huge",
  split: "train",
  streaming: true
)

# Lazy transformations (memory efficient)
stream
|> IterableDataset.filter(fn item -> item["score"] > 0.8 end)
|> IterableDataset.map(fn item -> preprocess(item) end)
|> IterableDataset.batch(32)
|> Enum.take(100)  # Only materializes 100 batches
```

### DatasetDict (Multiple Splits)

```elixir
alias HfDatasetsEx.DatasetDict

{:ok, dd} = HfDatasetsEx.load_dataset("squad")

# Access splits
train = dd["train"]
validation = dd["validation"]

# Operations across all splits
shuffled_dd = DatasetDict.shuffle(dd, seed: 42)
filtered_dd = DatasetDict.filter(dd, fn item -> item["is_valid"] end)

# Flatten to single dataset
all_data = DatasetDict.flatten(dd)
```

### Loading from Files

```elixir
alias HfDatasetsEx.Dataset

# Load from various file formats
{:ok, csv_ds} = Dataset.from_csv("/path/to/data.csv")
{:ok, json_ds} = Dataset.from_json("/path/to/data.json")
{:ok, parquet_ds} = Dataset.from_parquet("/path/to/data.parquet")
{:ok, text_ds} = Dataset.from_text("/path/to/data.txt")

# Bang versions raise on error
ds = Dataset.from_csv!("/path/to/data.csv")

# From generator (lazy by default)
stream = Dataset.from_generator(fn ->
  Stream.repeatedly(fn -> %{"x" => :rand.uniform()} end)
  |> Stream.take(1000)
end)

# Eager evaluation
ds = Dataset.from_generator(
  fn -> 1..100 |> Stream.map(&%{"x" => &1}) end,
  eager: true
)
```

### Exporting Datasets

```elixir
alias HfDatasetsEx.Dataset

# Export to various formats
Dataset.to_csv(dataset, "/path/to/output.csv")
Dataset.to_json(dataset, "/path/to/output.json")
Dataset.to_jsonl(dataset, "/path/to/output.jsonl")
Dataset.to_parquet(dataset, "/path/to/output.parquet")
Dataset.to_arrow(dataset, "/path/to/output.arrow")
Dataset.to_text(dataset, "/path/to/output.txt", column: "text")

# JSON with column orientation
Dataset.to_json(dataset, "/path/to/output.json", orient: :columns)
```

### Nx Tensor Formatting

```elixir
alias HfDatasetsEx.Dataset

# Set format for Nx tensors
dataset = Dataset.set_format(dataset, :nx, columns: ["input_ids", "labels"])

# Iteration returns tensors
Enum.each(dataset, fn row ->
  # row["input_ids"] is an Nx tensor
  Nx.sum(row["input_ids"])
end)

# Batch iteration with tensors
dataset
|> Dataset.iter(batch_size: 32)
|> Enum.each(fn batch ->
  # batch["input_ids"] is a stacked tensor of shape {32, ...}
  model_forward(batch)
end)

# Reset to default Elixir format
dataset = Dataset.reset_format(dataset)
```

### Vector Similarity Search

```elixir
alias HfDatasetsEx.Dataset

# Add embeddings to your dataset
dataset = Dataset.from_list([
  %{"id" => 1, "text" => "Hello", "embedding" => [0.1, 0.2, 0.3]},
  %{"id" => 2, "text" => "World", "embedding" => [0.4, 0.5, 0.6]},
  # ...
])

# Create a search index
dataset = Dataset.add_index(dataset, "embedding", metric: :cosine)

# Search for nearest neighbors
query = Nx.tensor([0.15, 0.25, 0.35])
{scores, examples} = Dataset.get_nearest_examples(dataset, "embedding", query, k: 5)

# Save/load index
Dataset.save_index(dataset, "embedding", "/path/to/index.idx")
{:ok, dataset} = Dataset.load_index(dataset, "embedding", "/path/to/index.idx")
```

### Push to HuggingFace Hub

```elixir
alias HfDatasetsEx.Dataset

# Requires HF_TOKEN environment variable or token option
{:ok, url} = Dataset.push_to_hub(dataset, "username/my-dataset")

# With options
{:ok, url} = Dataset.push_to_hub(dataset, "username/my-dataset",
  private: true,
  split: "train",
  token: "hf_xxx..."
)

# Push DatasetDict (all splits)
{:ok, url} = DatasetDict.push_to_hub(dataset_dict, "username/my-dataset")
```

### Type Casting

```elixir
alias HfDatasetsEx.{Dataset, Features}
alias HfDatasetsEx.Features.{ClassLabel, Value}

# Cast entire dataset to new schema
new_features = Features.new(%{
  "label" => ClassLabel.new(names: ["neg", "pos"]),
  "score" => %Value{dtype: :float32}
})
{:ok, casted} = Dataset.cast(dataset, new_features)

# Cast single column
{:ok, casted} = Dataset.cast_column(dataset, "label",
  ClassLabel.new(names: ["neg", "pos"])
)

# Auto-encode string column to integers
{:ok, encoded} = Dataset.class_encode_column(dataset, "category")
```

### Train/Test Split with Stratification

```elixir
alias HfDatasetsEx.Dataset

# Simple split
{:ok, %{train: train, test: test}} = Dataset.train_test_split(dataset,
  test_size: 0.2,
  seed: 42
)

# Stratified split (maintains class distribution)
{:ok, %{train: train, test: test}} = Dataset.train_test_split(dataset,
  test_size: 0.2,
  stratify_by_column: "label",
  seed: 42
)
```

### Custom Dataset Builders

```elixir
defmodule MyDataset do
  use HfDatasetsEx.DatasetBuilder

  @impl true
  def info do
    DatasetInfo.new(
      description: "My custom dataset",
      features: Features.new(%{
        "text" => %Value{dtype: :string},
        "label" => ClassLabel.new(names: ["neg", "pos"])
      })
    )
  end

  @impl true
  def split_generators(dl_manager, _config) do
    {:ok, train_path} = DownloadManager.download(dl_manager, @train_url)
    {:ok, test_path} = DownloadManager.download(dl_manager, @test_url)

    [
      SplitGenerator.new(:train, %{filepath: train_path}),
      SplitGenerator.new(:test, %{filepath: test_path})
    ]
  end

  @impl true
  def generate_examples(%{filepath: path}, _split) do
    path
    |> File.stream!()
    |> Stream.with_index()
    |> Stream.map(fn {line, idx} -> {idx, Jason.decode!(line)} end)
  end
end

# Build the dataset
{:ok, dataset_dict} = HfDatasetsEx.Builder.build(MyDataset)
{:ok, train} = HfDatasetsEx.Builder.build(MyDataset, split: :train)
```

### Features Schema

```elixir
alias HfDatasetsEx.Features

# Datasets include inferred feature schemas
dataset.features
# => %Features{
#      schema: %{
#        "question" => %Features.Value{dtype: :string},
#        "answer" => %Features.Value{dtype: :string},
#        "label" => %Features.ClassLabel{names: ["A", "B", "C", "D"]}
#      }
#    }

# Encode/decode class labels
Features.ClassLabel.encode(label_feature, "B")  # => 1
Features.ClassLabel.decode(label_feature, 1)    # => "B"
```

### Cache Management

```elixir
# List cached datasets
cached = HfDatasetsEx.list_cached()

# Invalidate specific cache
HfDatasetsEx.invalidate_cache("openai/gsm8k")

# Clear all cache
HfDatasetsEx.clear_cache()
```

## Architecture

```
HfDatasetsEx/
├── HfDatasetsEx                 # Main API
├── Dataset                      # Dataset struct + operations
├── DatasetDict                  # Split dictionary
├── IterableDataset              # Streaming dataset
├── Builder                      # Dataset builder runner
├── DatasetBuilder               # Builder behaviour
├── Features/                    # Features schema system
│   ├── Value                    # Scalar types
│   ├── ClassLabel               # Categorical
│   ├── Sequence                 # Lists
│   ├── Image                    # Image data
│   ├── Audio                    # Audio data
│   ├── Array2D-5D               # Multi-dimensional arrays
│   └── Translation              # Parallel text
├── Formatter/                   # Output formatting
│   ├── Elixir                   # Native Elixir (default)
│   ├── Nx                       # Nx tensors
│   ├── Explorer                 # Explorer DataFrames
│   └── Custom                   # Custom transforms
├── Index/                       # Search indices
│   └── BruteForce               # Similarity search
├── Source/                      # Data source abstraction
│   ├── Local                    # Local filesystem
│   └── HuggingFace              # HuggingFace Hub
├── Format/                      # File format parsers
│   ├── JSONL                    # JSON Lines
│   ├── JSON                     # JSON
│   ├── CSV                      # CSV/TSV
│   ├── Parquet                  # Parquet via Explorer
│   ├── Arrow                    # Arrow IPC
│   └── Text                     # Plain text
├── Export/                      # Export writers
│   ├── Arrow                    # Arrow IPC export
│   └── Text                     # Plain text export
├── Loader/                      # Dataset-specific loaders
│   ├── MMLU                     # MMLU loader
│   ├── HumanEval                # HumanEval loader
│   ├── GSM8K                    # GSM8K loader
│   ├── Math                     # MATH-500, DeepMath
│   ├── Chat                     # Tulu-3-SFT, No Robots
│   ├── Preference               # HH-RLHF, HelpSteer
│   ├── Code                     # DeepCoder
│   └── Vision                   # Vision datasets
├── Fetcher/
│   └── HuggingFace              # HuggingFace Hub API client
├── Hub                          # Hub upload operations
├── Cache                        # Local caching
├── TransformCache               # Transform result caching
├── Fingerprint                  # Operation fingerprinting
├── DownloadManager              # File download/extraction
├── Sampler                      # Sampling utilities
├── PRNG/                        # Random number generators
│   ├── PCG64                    # NumPy-compatible PRNG
│   └── SeedSequence             # Seed mixing
└── Types/                       # Structured data types
    ├── Message                  # Chat message
    ├── Conversation             # Multi-turn conversation
    └── Comparison               # Preference comparison
```

## Cache Directory

Datasets are cached in: `~/.hf_datasets_ex/datasets/`

```
datasets/
├── manifest.json              # Index of all cached datasets
├── openai__gsm8k/
│   └── main/
│       ├── train/
│       │   └── data.parquet
│       └── metadata.json
└── cais__mmlu/
```

## Sampling

```elixir
alias HfDatasetsEx.Sampler

# Random sampling
sample = Sampler.random_sample(dataset, size: 100, seed: 42)

# Stratified sampling
stratified = Sampler.stratified_sample(dataset,
  size: 200,
  strata_field: :subject
)

# K-fold cross-validation
folds = Sampler.k_fold(dataset, k: 5, shuffle: true, seed: 42)

Enum.each(folds, fn {train_fold, test_fold} ->
  # Train and evaluate on each fold
end)
```

## Reproducibility

HfDatasetsEx uses a NumPy-compatible PCG64 pseudo-random number generator by default, ensuring that seeded shuffles produce **identical results** to Python's HuggingFace `datasets` library.

```elixir
# This produces the same order as Python's:
# dataset.shuffle(seed=42)
shuffled = Dataset.shuffle(dataset, seed: 42)

# Explicitly specify the NumPy-compatible generator
shuffled = Dataset.shuffle(dataset, seed: 42, generator: :numpy)

# Use Erlang's native PRNG instead (faster, but different order than Python)
shuffled = Dataset.shuffle(dataset, seed: 42, generator: :erlang)
```

### Generator Options

| Generator | Description | Use Case |
|-----------|-------------|----------|
| `:numpy` (default) | PCG64 matching NumPy's implementation | Cross-language reproducibility with Python |
| `:erlang` | Erlang's native `exsss` algorithm | Performance-critical shuffling, no Python parity needed |

### Cross-Language Verification

```python
# Python
from datasets import load_dataset
ds = load_dataset("openai/gsm8k", split="train")
shuffled = ds.shuffle(seed=42)
print([ex["question"][:50] for ex in shuffled.select(range(3))])
```

```elixir
# Elixir - produces identical order
{:ok, ds} = HfDatasetsEx.load_dataset("openai/gsm8k", split: "train")
shuffled = HfDatasetsEx.Dataset.shuffle(ds, seed: 42)
shuffled |> Enum.take(3) |> Enum.map(& &1["question"] |> String.slice(0, 50))
```

## Testing

```bash
# Run the test suite
mix test

# Run live (network) tests
mix hf_datasets.test.live
```

## Static Analysis

```bash
# Run Dialyzer for type checking
mix dialyzer

# Run Credo for code quality
mix credo --strict

# Format code
mix format
```

## License

MIT License - see [LICENSE](LICENSE) file for details.
