# HfDatasetsEx Examples

This directory contains runnable examples demonstrating how to use HfDatasetsEx with various dataset types.

## Quick Start

Run all examples:

```bash
./examples/run_all.sh
```

Examples use live HuggingFace data. To run the helper script, set:

```bash
export HF_DATASETS_EX_LIVE_EXAMPLES=1
```

Or pass `--live`:

```bash
./examples/run_all.sh --live
```

If a dataset is gated, also set `HF_TOKEN`.

Or run individual examples:

```bash
mix run examples/math/gsm8k_example.exs
```

## Examples by Category

### Math Datasets

| Example | Description | Command |
|---------|-------------|---------|
| [gsm8k_example.exs](math/gsm8k_example.exs) | Load GSM8K from HuggingFace, sampling, train/test split | `mix run examples/math/gsm8k_example.exs` |
| [math500_example.exs](math/math500_example.exs) | MATH-500 problems, boxed answer extraction | `mix run examples/math/math500_example.exs` |

### Chat/Instruction Datasets

| Example | Description | Command |
|---------|-------------|---------|
| [tulu3_sft_example.exs](chat/tulu3_sft_example.exs) | Chat conversations, message handling (defaults to no_robots; pass tulu3_sft for full dataset) | `mix run examples/chat/tulu3_sft_example.exs` or `mix run examples/chat/tulu3_sft_example.exs -- tulu3_sft` |

### Preference/DPO Datasets

| Example | Description | Command |
|---------|-------------|---------|
| [hh_rlhf_example.exs](preference/hh_rlhf_example.exs) | HH-RLHF comparisons, preference labels | `mix run examples/preference/hh_rlhf_example.exs` |

### Code Datasets

| Example | Description | Command |
|---------|-------------|---------|
| [deepcoder_example.exs](code/deepcoder_example.exs) | DeepCoder code generation problems | `mix run examples/code/deepcoder_example.exs` |

### Core Functionality

| Example | Description | Command |
|---------|-------------|---------|
| [basic_usage.exs](basic_usage.exs) | Basic loading, sampling, splits, cache | `mix run examples/basic_usage.exs` |
| [load_dataset_example.exs](load_dataset_example.exs) | `load_dataset` API with repo_id/config/split | `mix run examples/load_dataset_example.exs` |
| [dataset_dict_example.exs](dataset_dict_example.exs) | DatasetDict split indexing | `mix run examples/dataset_dict_example.exs` |
| [streaming_example.exs](streaming_example.exs) | Streaming with IterableDataset | `mix run examples/streaming_example.exs` |
| [sampling_strategies.exs](sampling_strategies.exs) | Random, stratified, k-fold sampling | `mix run examples/sampling_strategies.exs` |
| [cross_validation.exs](cross_validation.exs) | K-fold cross-validation splits | `mix run examples/cross_validation.exs` |

### Vision Datasets

| Example | Description | Command |
|---------|-------------|---------|
| [vision_example.exs](vision/vision_example.exs) | Vision dataset loading + image features | `mix run examples/vision/vision_example.exs` |

## Dataset Loaders

### HuggingFace `load_dataset` API

```elixir
# Load by repo id
{:ok, dataset} = HfDatasetsEx.load_dataset("openai/gsm8k", config: "main", split: "train")

# Load all splits as DatasetDict
{:ok, dd} = HfDatasetsEx.load_dataset("openai/gsm8k")
train = dd["train"]

# Streaming
{:ok, iterable} =
  HfDatasetsEx.load_dataset("openai/gsm8k", split: "train", streaming: true)
```

### Loading Real Data from HuggingFace

```elixir
# GSM8K - Grade School Math
{:ok, gsm8k} = HfDatasetsEx.Loader.GSM8K.load(split: :train)

# MATH-500 - Competition Math
{:ok, math} = HfDatasetsEx.Loader.Math.load(:math_500)

# Chat datasets
{:ok, tulu} = HfDatasetsEx.Loader.Chat.load(:tulu3_sft)
{:ok, no_robots} = HfDatasetsEx.Loader.Chat.load(:no_robots)

# Preference datasets
{:ok, hh_rlhf} = HfDatasetsEx.Loader.Preference.load(:hh_rlhf)
{:ok, helpsteer} = HfDatasetsEx.Loader.Preference.load(:helpsteer3)

# Code datasets
{:ok, deepcoder} = HfDatasetsEx.Loader.Code.load(:deepcoder)
```

## Type System

### Conversations (Chat Datasets)

```elixir
alias HfDatasetsEx.Types.{Message, Conversation}

# Access conversation data
first_item = hd(dataset.items)
conv = first_item.input.conversation

# Message operations
Conversation.turn_count(conv)        # Number of turns
Conversation.last_message(conv)      # Last message
Conversation.system_prompt(conv)     # System prompt (if any)
Conversation.to_maps(conv)           # Convert to list of maps
```

### Comparisons (Preference Datasets)

```elixir
alias HfDatasetsEx.Types.{Comparison, LabeledComparison}

# Access comparison data
first_item = hd(dataset.items)
comp = first_item.input.comparison
label = first_item.expected

# Comparison fields
comp.prompt       # The prompt
comp.response_a   # First response
comp.response_b   # Second response

# Label operations
label.preferred                           # :a, :b, or :tie
LabeledComparison.is_preferred?(label, :a)  # true/false
LabeledComparison.to_score(label)           # 1.0, 0.0, or 0.5
```

## Sampling Operations

```elixir
alias HfDatasetsEx.Sampler

# Shuffle with seed
{:ok, shuffled} = Sampler.shuffle(dataset, seed: 42)

# Take first N items
{:ok, subset} = Sampler.take(dataset, 100)

# Skip first N items
{:ok, rest} = Sampler.skip(dataset, 100)

# Filter by predicate
{:ok, hard} = Sampler.filter(dataset, fn item ->
  item.metadata.difficulty == "hard"
end)

# Train/test split
{:ok, {train, test}} = Sampler.train_test_split(dataset, test_size: 0.2)

# K-fold cross-validation
{:ok, folds} = Sampler.k_fold(dataset, k: 5)
```

## Environment Variables

- `HF_TOKEN` - HuggingFace API token for authenticated access to private datasets
- `HF_DATASETS_EX_LIVE_EXAMPLES` - Set to `1` to run examples against live HF data

## Troubleshooting

### Network Issues

If you get network errors, verify connectivity and set `HF_TOKEN` for gated datasets.

### Large Datasets

Use `sample_size` to limit the number of items loaded:

```elixir
{:ok, dataset} = HfDatasetsEx.Loader.GSM8K.load(split: :train, sample_size: 1000)
```

### Memory Issues

For very large datasets, load and process in chunks:

```elixir
{:ok, dataset} = HfDatasetsEx.Loader.GSM8K.load(split: :train)
{:ok, chunk1} = Sampler.take(dataset, 1000)
{:ok, rest} = Sampler.skip(dataset, 1000)
# Process chunk1, then process rest...
```
