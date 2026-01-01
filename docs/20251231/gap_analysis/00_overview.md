# HuggingFace Datasets Port Gap Analysis Overview

**Date**: 2025-12-31
**Scope**: One-way gap analysis - features in Python `datasets` not yet in Elixir `hf_datasets_ex`

## Executive Summary

The Elixir port `hf_datasets_ex` v0.1.1 has solid foundational coverage of the Python `datasets` library (v4.4.3.dev0). However, significant gaps remain in advanced features, export functionality, and specialized data types.

## Current Port Status

| Category | Python Features | Elixir Port | Coverage |
|----------|----------------|-------------|----------|
| Core Dataset Class | 80+ methods | ~30 methods | 38% |
| DatasetDict | 40+ methods | ~15 methods | 38% |
| IterableDataset | 30+ methods | ~10 methods | 33% |
| Feature Types | 15 types | 6 types | 40% |
| I/O Formats (Read) | 21 formats | 4 formats | 19% |
| I/O Formats (Write) | 5 formats | 0 formats | 0% |
| Formatters | 9 formatters | 1 (Python dict) | 11% |
| Hub Integration | 5 operations | 1 operation | 20% |
| Builder Pattern | Full pattern | Not implemented | 0% |
| Caching/Fingerprint | Full system | Basic caching | 20% |
| Search/Indexing | FAISS, ES | None | 0% |

## Priority Classification

### P0 - Critical Gaps (Blocks Core ML Workflows)
1. **Export Functionality** - No `to_csv`, `to_json`, `to_parquet`
2. **NumPy/Nx Formatter** - Required for ML training pipelines
3. **Dataset Creation** - Missing `from_pandas`, `from_generator`

### P1 - High Priority (Common Use Cases)
1. **Missing Dataset Operations** - `cast`, `train_test_split` with stratify, `class_encode_column`
2. **Feature Types** - `Array2D-5D` for tensor data, `Translation` for NLP
3. **Text Format** - Simple text file loading
4. **Arrow Format** - Native Arrow read/write

### P2 - Medium Priority (Advanced Features)
1. **Hub Push** - `push_to_hub()` for sharing datasets
2. **Builder Pattern** - Custom dataset builders
3. **Fingerprinting** - Cache invalidation tracking
4. **Multi-processing** - `num_proc` parameter support

### P3 - Low Priority (Specialized)
1. **Search/Indexing** - FAISS, Elasticsearch
2. **Media Folders** - ImageFolder, AudioFolder, VideoFolder
3. **Specialized Formats** - HDF5, SQL, Spark, WebDataset
4. **Distributed** - Sharding across nodes

## Gap Documents

| Document | Coverage |
|----------|----------|
| [01_core_dataset_methods.md](./01_core_dataset_methods.md) | Dataset class methods not yet ported |
| [02_feature_types.md](./02_feature_types.md) | Missing feature type implementations |
| [03_io_formats.md](./03_io_formats.md) | I/O format readers and writers |
| [04_hub_integration.md](./04_hub_integration.md) | Hub push/delete operations |
| [05_formatters.md](./05_formatters.md) | Output formatters (NumPy, Pandas, etc.) |
| [06_caching_fingerprinting.md](./06_caching_fingerprinting.md) | Cache invalidation system |
| [07_builder_pattern.md](./07_builder_pattern.md) | DatasetBuilder infrastructure |
| [08_search_indexing.md](./08_search_indexing.md) | FAISS and Elasticsearch integration |

## Prompt Files

Each implementation task has a self-contained prompt file in the `prompts/` subdirectory:

| Prompt | Priority | Est. Complexity |
|--------|----------|-----------------|
| [01_export_formats.md](./prompts/01_export_formats.md) | P0 | Medium |
| [02_nx_formatter.md](./prompts/02_nx_formatter.md) | P0 | Medium |
| [03_dataset_creation.md](./prompts/03_dataset_creation.md) | P0 | Medium |
| [04_missing_dataset_ops.md](./prompts/04_missing_dataset_ops.md) | P1 | Medium |
| [05_array_feature_types.md](./prompts/05_array_feature_types.md) | P1 | High |
| [06_text_arrow_formats.md](./prompts/06_text_arrow_formats.md) | P1 | Low |
| [07_hub_push.md](./prompts/07_hub_push.md) | P2 | High |
| [08_builder_pattern.md](./prompts/08_builder_pattern.md) | P2 | High |
| [09_fingerprinting.md](./prompts/09_fingerprinting.md) | P2 | Medium |
| [10_search_indexing.md](./prompts/10_search_indexing.md) | P3 | High |

## Recommended Implementation Order

```
Phase 1: Core Functionality (P0)
  ├─ 01_export_formats.md     (to_csv, to_json, to_parquet)
  ├─ 02_nx_formatter.md       (Nx tensor output)
  └─ 03_dataset_creation.md   (from_generator, from_dataframe improvements)

Phase 2: Common Operations (P1)
  ├─ 04_missing_dataset_ops.md (cast, class_encode_column, etc.)
  ├─ 05_array_feature_types.md (Array2D-5D, Translation)
  └─ 06_text_arrow_formats.md  (Text, Arrow I/O)

Phase 3: Hub & Infrastructure (P2)
  ├─ 07_hub_push.md           (push_to_hub, delete_from_hub)
  ├─ 08_builder_pattern.md    (DatasetBuilder, BuilderConfig)
  └─ 09_fingerprinting.md     (Cache fingerprinting)

Phase 4: Advanced Features (P3)
  └─ 10_search_indexing.md    (FAISS, Elasticsearch)
```

## Architecture Considerations

### Elixir-Specific Adaptations

1. **No Mutation**: All operations return new structs (already implemented correctly)
2. **Streams vs Lists**: `IterableDataset` uses Elixir Streams (correct approach)
3. **Protocols**: Use Elixir protocols instead of Python duck typing
4. **NIFs/Ports**: Consider for performance-critical operations (FAISS, Arrow)
5. **Nx Integration**: Native Nx tensors instead of NumPy arrays

### Dependencies to Add

| Gap | Recommended Dependency |
|-----|----------------------|
| Arrow I/O | `adbc` (Arrow Database Connectivity) |
| HDF5 | `hdf5_ex` or NIF wrapper |
| SQL | `ecto` or `exqlite` |
| FAISS | Custom NIF or external service |
| Elasticsearch | `elasticsearch` or `elastix` |

## Metrics for Success

- Zero warnings from `mix compile`
- Zero issues from `mix credo --strict`
- Zero errors from `mix dialyzer`
- All tests pass with `mix test`
- 80%+ code coverage on new modules
