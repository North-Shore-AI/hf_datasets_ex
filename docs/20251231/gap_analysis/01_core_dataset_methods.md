# Gap Analysis: Core Dataset Methods

## Overview

The Python `datasets.Dataset` class (in `arrow_dataset.py`, 6,836 lines) contains 80+ methods. The Elixir `HfDatasetsEx.Dataset` module implements ~30 methods. This document catalogs the missing methods.

## Missing Dataset Methods

### Creation Methods (from_*)

| Python Method | Signature | Priority | Notes |
|---------------|-----------|----------|-------|
| `from_file` | `from_file(path, storage_options=None)` | P2 | Load from Arrow file |
| `from_buffer` | `from_buffer(buffer, features=None)` | P3 | Load from bytes buffer |
| `from_csv` | `from_csv(csv_file, features=None, ...)` | P1 | Have Format.CSV but not Dataset.from_csv |
| `from_json` | `from_json(json_file, features=None, ...)` | P1 | Have Format.JSON but not Dataset.from_json |
| `from_parquet` | `from_parquet(parquet_file, features=None, ...)` | P1 | Have Format.Parquet but not Dataset.from_parquet |
| `from_text` | `from_text(text_file, features=None, ...)` | P1 | Simple text file reading |
| `from_pandas` | `from_pandas(df, features=None, ...)` | P2 | N/A in Elixir - use from_dataframe |
| `from_polars` | `from_polars(df, features=None, ...)` | P3 | N/A - use from_dataframe |
| `from_generator` | `from_generator(function, features=None, ...)` | P0 | **Critical** - lazy dataset creation |
| `from_spark` | `from_spark(spark_df, features=None, ...)` | P3 | Spark integration |
| `from_sql` | `from_sql(sql, con, features=None, ...)` | P2 | SQL query to dataset |

### Transformation Methods

| Python Method | Signature | Priority | Notes |
|---------------|-----------|----------|-------|
| `cast` | `cast(features, batch_size=None, num_proc=None, ...)` | P1 | **Important** - change schema |
| `cast_column` | `cast_column(column_name, feature, ...)` | P1 | Cast single column |
| `class_encode_column` | `class_encode_column(column, include_nulls=False)` | P1 | Convert strings to ClassLabel |
| `align_labels_with_mapping` | `align_labels_with_mapping(label2id, label_column)` | P2 | Align labels with external mapping |
| `train_test_split` | `train_test_split(test_size=0.25, ..., stratify_by_column=None)` | P1 | Have split but no stratify |
| `repeat` | `repeat(num_times)` | P2 | Repeat dataset N times |

### Export Methods (to_*)

| Python Method | Signature | Priority | Notes |
|---------------|-----------|----------|-------|
| `to_csv` | `to_csv(csv_path, batch_size=None)` | P0 | **Critical** - export to CSV |
| `to_json` | `to_json(json_path, batch_size=None, orient='records')` | P0 | **Critical** - export to JSON |
| `to_parquet` | `to_parquet(parquet_path, batch_size=None)` | P0 | **Critical** - export to Parquet |
| `to_sql` | `to_sql(name, con, if_exists='fail', batch_size=None)` | P2 | Export to SQL database |
| `to_pandas` | `to_pandas(split=None)` | P2 | N/A - use to_dataframe |
| `to_polars` | `to_polars()` | P3 | N/A - use to_dataframe |
| `to_dict` | `to_dict(batch_size=None, batched=False)` | P1 | Column-oriented dict |
| `to_iterable_dataset` | `to_iterable_dataset(num_shards=1)` | P1 | Convert to lazy |

### Save/Load Methods

| Python Method | Signature | Priority | Notes |
|---------------|-----------|----------|-------|
| `save_to_disk` | `save_to_disk(dataset_path, ...)` | P1 | Save Arrow format locally |
| `load_from_disk` | `load_from_disk(dataset_path, ...)` | P1 | Load Arrow format |
| `push_to_hub` | `push_to_hub(repo_id, ...)` | P2 | Push to HuggingFace Hub |

### Format/Transform Methods

| Python Method | Signature | Priority | Notes |
|---------------|-----------|----------|-------|
| `set_format` | `set_format(type='python', columns=None, ...)` | P0 | **Critical** - output format |
| `with_format` | `with_format(type='torch', columns=None, ...)` | P0 | **Critical** - temporary format |
| `reset_format` | `reset_format()` | P1 | Reset to Python format |
| `formatted_as` | `formatted_as(type='pandas')` | P2 | Context manager for format |
| `with_transform` | `with_transform(transform, columns=None, ...)` | P2 | Apply transform on access |
| `set_transform` | `set_transform(transform, columns=None, ...)` | P2 | Persistent transform |

### Indexing Methods

| Python Method | Signature | Priority | Notes |
|---------------|-----------|----------|-------|
| `add_faiss_index` | `add_faiss_index(column, ...)` | P3 | Vector similarity search |
| `add_elasticsearch_index` | `add_elasticsearch_index(column, ...)` | P3 | Full-text search |
| `save_faiss_index` | `save_faiss_index(index_name, file)` | P3 | Persist FAISS index |
| `load_faiss_index` | `load_faiss_index(index_name, file)` | P3 | Load FAISS index |
| `drop_index` | `drop_index(index_name)` | P3 | Remove index |
| `get_nearest_examples` | `get_nearest_examples(column, query, k=10)` | P3 | kNN search |
| `search` | `search(column, query)` | P3 | Elasticsearch search |

### Utility Methods

| Python Method | Signature | Priority | Notes |
|---------------|-----------|----------|-------|
| `cleanup_cache_files` | `cleanup_cache_files()` | P2 | Remove temp cache |
| `info` | Property | P1 | DatasetInfo metadata |
| `features` | Property | P1 | Have features but not as property accessor |
| `builder_name` | Property | P2 | Builder that created dataset |
| `citation` | Property | P2 | BibTeX citation |
| `description` | Property | P2 | Human description |
| `homepage` | Property | P2 | Dataset URL |
| `license` | Property | P2 | License info |
| `num_rows` | Property | P1 | Have num_items |
| `num_columns` | Property | P1 | Column count |
| `column_names` | Property | Done | ✅ Implemented |
| `shape` | Property | P1 | (rows, columns) tuple |

### Iterator Methods

| Python Method | Signature | Priority | Notes |
|---------------|-----------|----------|-------|
| `iter` | `iter(batch_size=32)` | P1 | Batch iteration |
| `__iter__` | Iterator protocol | Done | ✅ Via Enumerable |
| `__getitem__` | Index/slice access | Done | ✅ Via Access protocol |
| `__len__` | Length | Done | ✅ Via Enumerable.count |

## Elixir Implementation Notes

### from_generator/1

```elixir
@spec from_generator((() -> Enumerable.t()), keyword()) :: t()
def from_generator(generator_fn, opts \\ []) do
  # Create IterableDataset from generator, optionally materialize
  stream = generator_fn.()

  if Keyword.get(opts, :eager, false) do
    items = Enum.to_list(stream)
    from_list(items, opts)
  else
    IterableDataset.from_stream(stream, opts)
  end
end
```

### cast/2

```elixir
@spec cast(t(), Features.t()) :: {:ok, t()} | {:error, term()}
def cast(%Dataset{} = dataset, %Features{} = new_features) do
  # Validate and cast each item to new schema
  with {:ok, casted_items} <- cast_items(dataset.items, new_features) do
    {:ok, %{dataset | items: casted_items, features: new_features}}
  end
end
```

### to_csv/2

```elixir
@spec to_csv(t(), Path.t(), keyword()) :: :ok | {:error, term()}
def to_csv(%Dataset{} = dataset, path, opts \\ []) do
  # Use NimbleCSV or :csv module
  headers = column_names(dataset)
  rows = Enum.map(dataset.items, fn item ->
    Enum.map(headers, &Map.get(item, &1, ""))
  end)

  content = NimbleCSV.RFC4180.dump_to_iodata([headers | rows])
  File.write(path, content)
end
```

## Testing Requirements

Each method needs:
1. Unit test with basic functionality
2. Edge cases (empty dataset, nil values)
3. Error handling tests
4. Property-based tests where applicable
5. Integration test with real data

## Files to Modify/Create

| File | Changes |
|------|---------|
| `lib/dataset_manager/dataset.ex` | Add missing methods |
| `lib/dataset_manager/export.ex` | New module for to_* functions |
| `lib/dataset_manager/format/output.ex` | Output formatting system |
| `test/dataset_manager/dataset_export_test.exs` | Export tests |
| `test/dataset_manager/dataset_creation_test.exs` | Creation tests |

## Dependencies

- `nimble_csv` - CSV export
- `jason` - Already have, JSON export
- `explorer` - Already have, Parquet export
