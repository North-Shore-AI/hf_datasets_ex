# HuggingFace Datasets Python Library - Comprehensive Feature Inventory

This document provides a complete inventory of the HuggingFace Datasets Python library features, serving as a reference for implementing equivalent functionality in `hf_datasets_ex`.

## Table of Contents

1. [Core API Functions](#1-core-api-functions)
2. [Dataset Class Methods](#2-dataset-class-methods)
3. [Data Processing Features](#3-data-processing-features)
4. [Streaming Capabilities](#4-streaming-capabilities)
5. [Caching and Fingerprinting](#5-caching-and-fingerprinting)
6. [Arrow/Parquet Integration](#6-arrowparquet-integration)
7. [Supported Dataset Formats](#7-supported-dataset-formats)
8. [Hub Integration Features](#8-hub-integration-features)
9. [Train/Test Splitting](#9-traintest-splitting)
10. [Batching and Iteration](#10-batching-and-iteration)
11. [Serialization](#11-serialization)
12. [Dataset Concatenation and Interleaving](#12-dataset-concatenation-and-interleaving)
13. [Type System (Features)](#13-type-system-features)
14. [Dataset Builder Patterns](#14-dataset-builder-patterns)
15. [Advanced Features](#15-advanced-features)

---

## 1. Core API Functions

### Primary Loading Functions

| Function | Description | Parameters |
|----------|-------------|------------|
| `load_dataset(path, ...)` | Load dataset from Hub or local files | `path`, `name`, `data_dir`, `data_files`, `split`, `cache_dir`, `features`, `download_config`, `download_mode`, `verification_mode`, `keep_in_memory`, `revision`, `token`, `streaming`, `num_proc`, `storage_options` |
| `load_from_disk(path)` | Load previously saved dataset | `dataset_path`, `keep_in_memory`, `storage_options` |
| `load_dataset_builder(path)` | Get dataset builder without loading | Same as `load_dataset` except `split`, `streaming` |

### Inspection Functions

| Function | Description |
|----------|-------------|
| `get_dataset_config_names(path)` | Get available configuration names |
| `get_dataset_infos(path)` | Get metadata for all configs |
| `get_dataset_split_names(path)` | Get available split names |

### Download Modes

| Mode | Description |
|------|-------------|
| `REUSE_DATASET_IF_EXISTS` | Default - reuse cached data |
| `REUSE_CACHE_IF_EXISTS` | Reuse downloaded files, regenerate dataset |
| `FORCE_REDOWNLOAD` | Force re-download everything |

### Verification Modes

| Mode | Description |
|------|-------------|
| `NO_CHECKS` | Skip all verification |
| `BASIC_CHECKS` | Default - basic integrity checks |
| `ALL_CHECKS` | Full verification including checksums |

---

## 2. Dataset Class Methods

### Creation Methods (Static/Class Methods)

| Method | Description |
|--------|-------------|
| `Dataset.from_dict(mapping)` | Create from Python dictionary |
| `Dataset.from_pandas(df)` | Create from pandas DataFrame |
| `Dataset.from_generator(generator)` | Create from generator function |
| `Dataset.from_file(filename)` | Create from Arrow file |
| `Dataset.from_buffer(buffer)` | Create from Arrow buffer |
| `Dataset.from_csv(path)` | Create from CSV file(s) |
| `Dataset.from_json(path)` | Create from JSON/JSONL file(s) |
| `Dataset.from_parquet(path)` | Create from Parquet file(s) |
| `Dataset.from_text(path)` | Create from text file(s) |
| `Dataset.from_sql(sql, con)` | Create from SQL query/table |

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `data` | Arrow Table | Underlying PyArrow table |
| `cache_files` | list | Cache file paths |
| `num_columns` | int | Number of columns |
| `num_rows` | int | Number of rows |
| `column_names` | list[str] | Column names |
| `shape` | tuple | (num_rows, num_columns) |
| `info` | DatasetInfo | Dataset metadata |
| `features` | Features | Schema definition |
| `split` | str | Named split (train/test/etc.) |

### Indexing and Iteration

| Method/Operation | Description |
|------------------|-------------|
| `__getitem__(key)` | Access by column name or index |
| `__len__()` | Number of rows |
| `__iter__()` | Iterate through examples |
| `iter(batch_size)` | Iterate in batches |

---

## 3. Data Processing Features

### Transform Methods

| Method | Description | Key Parameters |
|--------|-------------|----------------|
| `map(function)` | Apply function to examples | `batched`, `batch_size`, `with_indices`, `with_rank`, `input_columns`, `remove_columns`, `num_proc` |
| `filter(function)` | Filter examples by predicate | `batched`, `batch_size`, `with_indices`, `input_columns` |
| `select(indices)` | Select rows by indices | `indices`, `keep_in_memory` |
| `sort(column)` | Sort by column values | `column_names`, `reverse`, `null_placement` |
| `shuffle(seed)` | Shuffle rows | `seed`, `generator`, `keep_in_memory` |
| `flatten()` | Flatten nested structures | - |
| `unique(column)` | Get unique values | `column` |

### Column Operations

| Method | Description |
|--------|-------------|
| `add_column(name, column)` | Add new column |
| `remove_columns(column_names)` | Remove column(s) |
| `rename_column(old, new)` | Rename single column |
| `rename_columns(mapping)` | Rename multiple columns |
| `select_columns(column_names)` | Keep only specified columns |
| `cast(features)` | Cast all columns to new types |
| `cast_column(column, feature)` | Cast single column |
| `class_encode_column(column)` | Convert to ClassLabel |

### Subset Operations

| Method | Description | Key Parameters |
|--------|-------------|----------------|
| `skip(n)` | Skip first n examples | `n` |
| `take(n)` | Take first n examples | `n` |
| `train_test_split()` | Split into train/test | `test_size`, `train_size`, `shuffle`, `stratify_by_column`, `seed` |
| `shard(num_shards, index)` | Get one shard of dataset | `num_shards`, `index`, `contiguous` |
| `repeat(num_times)` | Repeat dataset | `num_times` |

### Data Item Operations

| Method | Description |
|--------|-------------|
| `add_item(item)` | Add single example |
| `align_labels_with_mapping(label2id, column)` | Align labels with model mapping |

---

## 4. Streaming Capabilities

### IterableDataset

`IterableDataset` provides lazy/streaming data loading without downloading entire dataset.

#### Key Differences from Dataset

| Feature | Dataset | IterableDataset |
|---------|---------|-----------------|
| Random access | Yes | No (sequential only) |
| Length known | Yes | No (until exhausted) |
| Memory usage | Memory-mapped | Streaming |
| Indexing | `dataset[i]` | Must iterate |

#### IterableDataset Methods

| Method | Description |
|--------|-------------|
| `map(function)` | Lazy transformation |
| `filter(function)` | Lazy filtering |
| `skip(n)` | Skip first n examples |
| `take(n)` | Take first n examples |
| `shuffle(buffer_size)` | Approximate shuffle with buffer |
| `shard(num_shards, index)` | Get one shard |
| `batch(batch_size)` | Group into batches |
| `iter(batch_size)` | Iterate in batches |

#### Streaming Configuration

```python
# Enable streaming
dataset = load_dataset("dataset_name", streaming=True)

# Buffer-based shuffling
dataset = dataset.shuffle(seed=42, buffer_size=1000)
```

#### Stateful Iteration (Checkpointing)

| Method | Description |
|--------|-------------|
| `state_dict()` | Get current iteration state |
| `load_state_dict(state)` | Resume from checkpoint |

---

## 5. Caching and Fingerprinting

### Fingerprinting Mechanism

The fingerprinting system enables intelligent caching:

1. **Initial fingerprint**: Computed from Arrow table hash or Arrow file hash
2. **Transform fingerprint**: Combined from previous fingerprint + transform hash
3. **Hash computation**: Uses `dill` serialization + `xxhash`

### Caching Behavior

| Scenario | Behavior |
|----------|----------|
| Same transforms, same session | Reuses cache |
| Same transforms, different session | Reuses cache (deterministic) |
| Non-hashable transform | Random fingerprint + warning |
| Caching disabled | Temporary files, deleted on session end |

### Cache Control Functions

| Function | Description |
|----------|-------------|
| `enable_caching()` | Enable dataset caching |
| `disable_caching()` | Disable dataset caching |
| `is_caching_enabled()` | Check caching status |
| `Dataset.cleanup_cache_files()` | Remove unused cache files |
| `Dataset.flatten_indices()` | Rewrite dataset to remove indices mapping |

### Cache Configuration

```python
# Global cache directory
datasets.config.HF_DATASETS_CACHE = "~/.cache/huggingface/datasets"

# In-memory threshold
datasets.config.IN_MEMORY_MAX_SIZE = 0  # 0 = always memory-map
```

---

## 6. Arrow/Parquet Integration

### Apache Arrow Features

| Feature | Description |
|---------|-------------|
| Memory mapping | Zero-copy reads from disk |
| Columnar format | Efficient column-wise operations |
| Nested types | Support for complex nested structures |
| Type system | Rich type definitions |

### Parquet Features

| Feature | Description |
|---------|-------------|
| Compression | Efficient storage |
| Predicate pushdown | Filter before loading |
| Column pruning | Load only needed columns |
| Row group filtering | Skip irrelevant data |

### Parquet-specific Parameters

```python
load_dataset("parquet",
    columns=["col1", "col2"],           # Column selection
    filters=[("col", "==", value)],     # Predicate pushdown
    batch_size=10000,                   # Read batch size
    fragment_scan_options=...           # Advanced scanning options
)
```

---

## 7. Supported Dataset Formats

### Built-in Format Handlers

| Format | Builder Name | File Extensions |
|--------|--------------|-----------------|
| CSV | `csv` | `.csv` |
| JSON/JSONL | `json` | `.json`, `.jsonl` |
| Parquet | `parquet` | `.parquet` |
| Arrow | `arrow` | `.arrow` |
| Text | `text` | `.txt` |
| XML | `xml` | `.xml` |
| SQL | `sql` | N/A (database) |
| HDF5 | `hdf5` | `.h5`, `.hdf5` |

### Folder-based Formats (Multimodal)

| Format | Builder Name | Description |
|--------|--------------|-------------|
| ImageFolder | `imagefolder` | Images organized in folders |
| AudioFolder | `audiofolder` | Audio files in folders |
| VideoFolder | `videofolder` | Video files in folders |
| PdfFolder | `pdffolder` | PDF documents in folders |
| NiftiFolder | `niftifolder` | Medical imaging (NIfTI) |
| WebDataset | `webdataset` | Sharded tar archives |

### Format-specific Configurations

#### CSV Configuration
- `sep` (delimiter)
- `header` (row with column names)
- `column_names` (explicit names)
- `skip_rows`
- `encoding`

#### JSON Configuration
- `field` (nested field to extract)
- `lines` (JSON Lines format)

#### Parquet Configuration
- `columns` (column selection)
- `filters` (predicate pushdown)
- `batch_size`

---

## 8. Hub Integration Features

### Uploading to Hub

| Method | Description |
|--------|-------------|
| `push_to_hub(repo_id)` | Upload dataset to Hub |
| Parameters: | `config_name`, `split`, `private`, `token`, `revision`, `create_pr`, `max_shard_size`, `num_shards`, `embed_external_files` |

### Hub Operations

```python
# Push to Hub
dataset.push_to_hub("username/dataset_name", private=True)

# Load specific revision
dataset = load_dataset("username/dataset_name", revision="v1.0.0")

# Load with authentication
dataset = load_dataset("username/dataset_name", token="hf_...")
```

### Dataset Cards

Datasets on Hub can have:
- README.md with metadata
- YAML front matter for configuration
- License information
- Citation information

---

## 9. Train/Test Splitting

### `train_test_split()` Method

```python
dataset.train_test_split(
    test_size=0.2,              # Proportion or absolute count
    train_size=None,            # Optional explicit train size
    shuffle=True,               # Shuffle before split
    stratify_by_column=None,    # Stratified sampling
    seed=42,                    # Random seed
    generator=None              # NumPy random generator
)
```

Returns: `DatasetDict` with 'train' and 'test' keys

### Split Slicing

```python
# Load specific portions
dataset = load_dataset("dataset", split="train[:1000]")
dataset = load_dataset("dataset", split="train[50%:]")
dataset = load_dataset("dataset", split="train[:10%]+test[:10%]")
```

### ReadInstruction API

```python
from datasets import ReadInstruction

# More programmatic control
ri = ReadInstruction("train", from_=0, to=10, unit="abs")
dataset = load_dataset("dataset", split=ri)
```

---

## 10. Batching and Iteration

### Basic Iteration

```python
# Single examples
for example in dataset:
    process(example)

# Batched iteration
for batch in dataset.iter(batch_size=32):
    process_batch(batch)
```

### Framework Integration

#### PyTorch DataLoader

```python
# Set format
dataset = dataset.with_format("torch")

# Use with DataLoader
from torch.utils.data import DataLoader
dataloader = DataLoader(dataset, batch_size=32, num_workers=4)
```

#### TensorFlow Dataset

```python
tf_dataset = dataset.to_tf_dataset(
    batch_size=32,
    columns=["input_ids", "attention_mask"],
    shuffle=True,
    collate_fn=data_collator
)
```

### Stateful DataLoader (Checkpointing)

```python
from torchdata.stateful_dataloader import StatefulDataLoader

dataloader = StatefulDataLoader(dataset, batch_size=32)
# Save state
state = dataloader.state_dict()
# Resume
dataloader.load_state_dict(state)
```

---

## 11. Serialization

### Save to Disk (Arrow Format)

```python
# Save
dataset.save_to_disk("path/to/dataset")

# Load
dataset = load_from_disk("path/to/dataset")
```

Parameters:
- `max_shard_size`: Maximum shard size (e.g., "500MB")
- `num_shards`: Explicit number of shards
- `num_proc`: Parallel processes
- `storage_options`: For remote storage (S3, etc.)

### Export Methods

| Method | Output Format |
|--------|---------------|
| `to_csv(path)` | CSV file |
| `to_json(path)` | JSON/JSONL file |
| `to_parquet(path)` | Parquet file |
| `to_pandas()` | pandas DataFrame |
| `to_dict()` | Python dictionary |
| `to_sql(table, connection)` | SQL database |

### Format Comparison

| Format | Use Case |
|--------|----------|
| Arrow (save_to_disk) | Fast local caching, ephemeral |
| Parquet (to_parquet) | Long-term storage, sharing |
| CSV/JSON | Interoperability |

---

## 12. Dataset Concatenation and Interleaving

### Concatenation

```python
from datasets import concatenate_datasets

# Vertical concatenation (stack rows)
combined = concatenate_datasets([dataset1, dataset2])

# Horizontal concatenation (add columns)
combined = concatenate_datasets([dataset1, dataset2], axis=1)
```

Requirements:
- Same column types for vertical
- Same number of rows for horizontal

### Interleaving

```python
from datasets import interleave_datasets

# Round-robin interleaving
combined = interleave_datasets([ds1, ds2, ds3])

# Probability-weighted sampling
combined = interleave_datasets(
    [ds1, ds2, ds3],
    probabilities=[0.7, 0.2, 0.1],
    seed=42
)
```

### Stopping Strategies

| Strategy | Description |
|----------|-------------|
| `first_exhausted` | Stop when any dataset exhausted |
| `all_exhausted` | Stop when all datasets exhausted (with replacement) |
| `all_exhausted_without_replacement` | Each sample used exactly once |

---

## 13. Type System (Features)

### Core Feature Types

| Type | Description | Example |
|------|-------------|---------|
| `Value(dtype)` | Scalar values | `Value('int32')`, `Value('string')` |
| `ClassLabel(names)` | Categorical labels | `ClassLabel(names=['neg', 'pos'])` |
| `Sequence(feature)` | Variable-length list | `Sequence(Value('int32'))` |

### Value Data Types

- Integers: `int8`, `int16`, `int32`, `int64`
- Unsigned: `uint8`, `uint16`, `uint32`, `uint64`
- Floats: `float16`, `float32`, `float64`
- Other: `bool`, `string`, `binary`
- Temporal: `date32`, `date64`, `time32`, `time64`, `timestamp`

### Multidimensional Arrays

| Type | Description |
|------|-------------|
| `Array2D(shape, dtype)` | 2D array |
| `Array3D(shape, dtype)` | 3D array |
| `Array4D(shape, dtype)` | 4D array |
| `Array5D(shape, dtype)` | 5D array |

Dynamic first dimension: `Array3D(shape=(None, 5, 2), dtype='int32')`

### Multimodal Features

| Type | Description | Decode Option |
|------|-------------|---------------|
| `Image()` | Image data | `decode=True/False` |
| `Audio(sampling_rate)` | Audio data | `decode=True/False` |
| `Video()` | Video data | `decode=True/False` |

### Translation Features

| Type | Description |
|------|-------------|
| `Translation(languages)` | Fixed languages per example |
| `TranslationVariableLanguages(languages)` | Variable languages per example |

### Nested Structures

```python
Features({
    'text': Value('string'),
    'label': ClassLabel(names=['neg', 'pos']),
    'metadata': {
        'source': Value('string'),
        'timestamp': Value('timestamp[s]')
    },
    'tokens': Sequence(Value('string')),
    'embeddings': Array2D(shape=(None, 768), dtype='float32')
})
```

### ClassLabel Methods

| Method | Description |
|--------|-------------|
| `int2str(value)` | Convert int to label string |
| `str2int(value)` | Convert label string to int |
| `names` | List of label names |
| `num_classes` | Number of classes |

---

## 14. Dataset Builder Patterns

### DatasetBuilder Base Class

```python
class MyDatasetBuilder(datasets.GeneratorBasedBuilder):
    """Custom dataset builder."""

    VERSION = datasets.Version("1.0.0")

    def _info(self):
        """Define dataset metadata and features."""
        return datasets.DatasetInfo(
            description="...",
            features=datasets.Features({...}),
            supervised_keys=("input", "label"),
            homepage="...",
            citation="..."
        )

    def _split_generators(self, dl_manager):
        """Download and define splits."""
        data_dir = dl_manager.download_and_extract("url")
        return [
            datasets.SplitGenerator(
                name=datasets.Split.TRAIN,
                gen_kwargs={"filepath": data_dir / "train.csv"}
            ),
            datasets.SplitGenerator(
                name=datasets.Split.TEST,
                gen_kwargs={"filepath": data_dir / "test.csv"}
            )
        ]

    def _generate_examples(self, filepath):
        """Yield examples."""
        with open(filepath) as f:
            for idx, line in enumerate(f):
                yield idx, {"text": line.strip()}
```

### BuilderConfig

```python
class MyBuilderConfig(datasets.BuilderConfig):
    """Config for dataset variants."""

    def __init__(self, subset_name, **kwargs):
        super().__init__(**kwargs)
        self.subset_name = subset_name

class MyDatasetBuilder(datasets.GeneratorBasedBuilder):
    BUILDER_CONFIGS = [
        MyBuilderConfig(name="subset1", subset_name="a"),
        MyBuilderConfig(name="subset2", subset_name="b"),
    ]
```

### DownloadManager

| Method | Description |
|--------|-------------|
| `download(url)` | Download file |
| `download_and_extract(url)` | Download and extract archive |
| `extract(path)` | Extract local archive |
| `iter_archive(path)` | Iterate archive contents |
| `iter_files(path)` | Iterate directory files |

---

## 15. Advanced Features

### Memory Mapping

Datasets uses Apache Arrow memory mapping for efficient access:

```python
# Default: memory-mapped
dataset = load_dataset("dataset_name")

# Force in-memory
dataset = load_dataset("dataset_name", keep_in_memory=True)

# Configure threshold
datasets.config.IN_MEMORY_MAX_SIZE = 1e9  # 1GB
```

### Distributed Processing

```python
from datasets.distributed import split_dataset_by_node

# Split for distributed training
dataset = split_dataset_by_node(dataset, rank=0, world_size=8)
```

With PyTorch distributed:

```python
import torch.distributed

if training_args.local_rank > 0:
    torch.distributed.barrier()

dataset = dataset.map(process_fn)

if training_args.local_rank == 0:
    torch.distributed.barrier()
```

### Multiprocessing

```python
# Parallel map
dataset = dataset.map(process_fn, num_proc=4)

# Parallel loading
dataset = load_dataset("dataset_name", num_proc=4)
```

### Search Index Integration

#### FAISS (Dense Retrieval)

```python
# Add FAISS index
dataset.add_faiss_index(column='embeddings')

# Search
scores, examples = dataset.get_nearest_examples('embeddings', query_vector, k=10)

# Save/load index
dataset.save_faiss_index('embeddings', 'index.faiss')
dataset.load_faiss_index('embeddings', 'index.faiss')
```

#### Elasticsearch (Text Search)

```python
# Add Elasticsearch index
dataset.add_elasticsearch_index(column='text', es_index_name='my_index')

# Search
scores, examples = dataset.get_nearest_examples('text', 'query text', k=10)
```

### Formatting

```python
# Temporary format (returns new dataset)
torch_dataset = dataset.with_format("torch")
numpy_dataset = dataset.with_format("numpy")

# In-place format (modifies dataset)
dataset.set_format("torch", columns=["input_ids"])
dataset.reset_format()

# Custom transform
dataset.set_transform(lambda batch: tokenizer(batch['text']))
```

Supported formats: `None`, `numpy`, `torch`, `tensorflow`, `jax`, `arrow`, `pandas`, `polars`

### Data Verification

| Check | Description |
|-------|-------------|
| Checksum verification | Verify downloaded file integrity |
| Size validation | Verify file sizes |
| Split validation | Verify split information |
| Feature validation | Verify schema consistency |

### Performance Optimization

| Technique | Use Case |
|-----------|----------|
| `flatten_indices()` | After shuffle/sort for faster access |
| `with_format("arrow")` | Zero-copy access |
| Streaming | Large datasets that don't fit in memory |
| `num_proc` | Parallel processing |
| Column selection | Load only needed columns |

---

## DatasetDict

`DatasetDict` is a dictionary of splits with methods applied to all splits:

```python
dataset_dict = load_dataset("dataset_name")  # Returns DatasetDict

# Apply to all splits
dataset_dict = dataset_dict.map(process_fn)
dataset_dict = dataset_dict.filter(filter_fn)

# Access individual splits
train = dataset_dict["train"]
test = dataset_dict["test"]
```

All Dataset methods are available on DatasetDict and apply to each split.

---

## Summary Statistics

| Category | Count |
|----------|-------|
| Loading functions | 4 |
| Dataset creation methods | 10 |
| Transform methods | 7 |
| Column operations | 7 |
| Subset operations | 6 |
| Export methods | 6 |
| Feature types | 15+ |
| Format handlers | 13+ |
| Indexing methods | 6+ |

---

## Sources

- [HuggingFace Datasets Documentation](https://huggingface.co/docs/datasets/en/index)
- [Main Classes Reference](https://huggingface.co/docs/datasets/package_reference/main_classes)
- [Loading Methods Reference](https://huggingface.co/docs/datasets/package_reference/loading_methods)
- [Builder Classes Reference](https://huggingface.co/docs/datasets/en/package_reference/builder_classes)
- [Process Documentation](https://huggingface.co/docs/datasets/en/process)
- [Stream Documentation](https://huggingface.co/docs/datasets/en/stream)
- [Dataset Features Documentation](https://huggingface.co/docs/datasets/about_dataset_features)
- [Cache Documentation](https://huggingface.co/docs/datasets/about_cache)
- [GitHub Repository](https://github.com/huggingface/datasets)
