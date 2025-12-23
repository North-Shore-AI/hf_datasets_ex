# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2025-12-22

### Added

- **HuggingFace Parity API:** `load_dataset/2` with repo_id/config/split/streaming options
- **Data Discovery:** DataFiles resolver using HfHub API for config + split discovery
- **Dataset Types:**
  - `Dataset` - Core dataset struct with comprehensive operations
  - `DatasetDict` - Dictionary of splits with Python-like bracket access
  - `IterableDataset` - Lazy streaming for memory-efficient processing
- **Streaming:** JSONL line-by-line streaming; Parquet batch streaming support
- **Features Schema System:**
  - `Value` - Scalar types (int8-64, uint8-64, float16-64, string, bool, binary)
  - `ClassLabel` - Categorical with encode/decode
  - `Sequence` - Lists with fixed length support
  - `Image` - Image data with Vix/libvips decode
- **Source Abstraction:**
  - `Source.Local` - Local filesystem source
  - `Source.HuggingFace` - HuggingFace Hub source
- **Format Parsers:**
  - JSONL, JSON, CSV, Parquet (via Explorer)
- **Dataset Operations:**
  - `map/2`, `filter/2`, `shuffle/2`, `select/2`
  - `take/2`, `skip/2`, `slice/3`, `batch/2`
  - `concat/1,2`, `split/2`, `shard/2`
  - Column operations: `rename_column/3`, `add_column/3`, `remove_columns/2`
  - `unique/2`, `sort/2`, `flatten/2`
  - Enumerable protocol and Access behaviour
- **Dataset Loaders:**
  - MMLU, HumanEval, GSM8K
  - Math (MATH-500, DeepMath, POLARIS)
  - Chat (Tulu-3-SFT, No Robots)
  - Preference (HH-RLHF, HelpSteer2/3, UltraFeedback)
  - Code (DeepCoder)
  - Vision (Caltech101, Oxford Flowers 102, Oxford-IIIT Pet, Stanford Cars)
- **Sampling:** Random, stratified, k-fold cross-validation
- **Caching:** Automatic local caching with version tracking
- **Structured Types:** Message, Conversation, Comparison for chat/preference data
