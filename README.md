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
- **Features Schema**: Value/ClassLabel/Sequence/Image + inference
- **Image Decode**: Vix/libvips integration for vision datasets
- **Automatic Caching**: Fast access with local caching and version tracking
- **Dataset Operations**: map, filter, shuffle, select, take, skip, batch, concat, split
- **NumPy-Compatible Shuffling**: PCG64 PRNG matches Python's `datasets.shuffle(seed=N)` exactly
- **Reproducibility**: Deterministic sampling with seeds, version tracking
- **Extensible**: Easy integration of custom datasets and sources

## Installation

Add `hf_datasets_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hf_datasets_ex, "~> 0.1.1"}
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
├── Features                     # Features schema system
│   ├── Value                    # Scalar types
│   ├── ClassLabel               # Categorical
│   ├── Sequence                 # Lists
│   └── Image                    # Image data
├── Source/                      # Data source abstraction
│   ├── Local                    # Local filesystem
│   └── HuggingFace              # HuggingFace Hub
├── Format/                      # File format parsers
│   ├── JSONL                    # JSON Lines
│   ├── JSON                     # JSON
│   ├── CSV                      # CSV
│   └── Parquet                  # Parquet via Explorer
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
├── Cache                        # Local caching
├── Sampler                      # Sampling utilities
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
mix test.live
```

## Static Analysis

```bash
# Run Dialyzer
mix dialyzer
```

## License

MIT License - see [LICENSE](LICENSE) file for details.
