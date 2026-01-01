# Changelog

All notable changes to this project will be documented in this file.

## [0.1.2] - 2025-12-31

### Added

- **Dataset Builder Pattern:** Custom dataset builders with `use HfDatasetsEx.DatasetBuilder` behaviour
  - `Builder` module for running builders to produce Dataset/DatasetDict
  - `BuilderConfig` for builder variant configuration
  - `SplitGenerator` for defining split generation
  - `DatasetInfo` for dataset metadata
  - `DownloadManager` for file downloads and archive extraction

- **Output Formatting System:** Format dataset outputs for different backends
  - `Dataset.set_format/3`, `with_format/3`, `reset_format/1` for format control
  - `Formatter.Nx` - Convert numeric data to Nx tensors
  - `Formatter.Explorer` - Convert to Explorer DataFrames
  - `Formatter.Custom` - Apply custom transform functions
  - `Dataset.iter/2` - Batch iteration with formatting applied

- **Vector Similarity Search:** Built-in search indices for embeddings
  - `Dataset.add_index/3` - Add search index to a column
  - `Dataset.get_nearest_examples/4` - Find nearest neighbors
  - `Dataset.save_index/3`, `load_index/3`, `drop_index/2` - Index persistence
  - `Index.BruteForce` - Pure Elixir cosine/L2/inner-product similarity

- **Type Casting & Encoding:**
  - `Dataset.cast/2` - Cast dataset to new feature schema
  - `Dataset.cast_column/3` - Cast single column
  - `Dataset.class_encode_column/2` - Auto-encode strings to ClassLabel integers

- **Enhanced Train/Test Split:**
  - `Dataset.train_test_split/2` with stratification support
  - Options: `:test_size`, `:train_size`, `:stratify_by_column`, `:seed`, `:shuffle`

- **Data Loading from Files:**
  - `Dataset.from_generator/2` - Create from generator function (lazy or eager)
  - `Dataset.from_csv/2`, `from_csv!/2` - Load from CSV files
  - `Dataset.from_json/2`, `from_json!/2` - Load from JSON/JSONL files
  - `Dataset.from_parquet/2`, `from_parquet!/2` - Load from Parquet files
  - `Dataset.from_text/2`, `from_text!/2` - Load from plain text (line per row)
  - `Loader.load_from_file/2` - Generic file loading

- **Export Functions:**
  - `Dataset.to_csv/3` - Export to CSV
  - `Dataset.to_json/3` - Export to JSON (records or columns format)
  - `Dataset.to_jsonl/3` - Export to JSON Lines
  - `Dataset.to_parquet/3` - Export to Parquet
  - `Dataset.to_text/3` - Export to plain text
  - `Dataset.to_arrow/3` - Export to Arrow IPC format

- **HuggingFace Hub Integration:**
  - `Dataset.push_to_hub/3` - Upload dataset to HuggingFace Hub
  - `DatasetDict.push_to_hub/3` - Upload all splits
  - `Hub.delete_from_hub/3` - Delete dataset config from Hub
  - Automatic sharding, dataset card generation, and repo creation

- **Transform Caching:**
  - `Fingerprint` module for deterministic operation fingerprinting
  - `TransformCache` for caching transformation results
  - Automatic cache invalidation on input/operation changes
  - `Dataset.map/3` and `filter/3` now support `:cache` option

- **New Feature Types:**
  - `Array2D`, `Array3D`, `Array4D`, `Array5D` - Fixed-shape multi-dimensional arrays
  - `Translation` - Fixed-language parallel text
  - `TranslationVariableLanguages` - Variable-language translations

- **New Format Parsers:**
  - `Format.Arrow` - Apache Arrow IPC format parser
  - `Format.Text` - Plain text file parser (line per row)
  - TSV support via CSV parser with delimiter option

- **Utility Functions:**
  - `Dataset.to_dict/2` - Convert to column-oriented dictionary
  - `Dataset.fingerprint/1` - Get/compute dataset fingerprint
  - `Config` module for application configuration
  - Offline mode support via `HF_DATASETS_OFFLINE=1`

### Changed

- **Format Detection:** Now returns `{:ok, module, opts}` tuples for better extensibility
- **Map/Filter:** Added `:batched` and `:batch_size` options for batch processing
- **Dataset struct:** Added `fingerprint`, `format`, `format_columns`, `format_opts` fields
- **Enumerable implementation:** Now respects format settings during iteration

### Dependencies

- Added `nx ~> 0.9` for tensor operations
- Added `credo ~> 1.7` for static code analysis


## [0.1.1] - 2025-12-23

### Added

- **NumPy-compatible PRNG:** PCG64 pseudo-random number generator matching NumPy's implementation for exact shuffle parity with Python's `datasets.shuffle(seed=N)`
- **SeedSequence:** Hash-based seed mixing algorithm matching NumPy's seeding behavior
- **Generator option for shuffle:** `Dataset.shuffle/2` now accepts `:generator` option (`:numpy` default, or `:erlang`)

### Changed

- **Updated logo:** Refreshed dataset overlay colors and positioning in SVG asset
- **README layout:** Centered logo with improved styling

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
