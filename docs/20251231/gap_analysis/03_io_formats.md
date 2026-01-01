# Gap Analysis: I/O Formats

## Overview

The Python `datasets` library supports 21 input formats and 5 output formats via the `packaged_modules/` directory. The Elixir port currently supports 4 input formats and 0 output formats.

## Current Elixir Implementation

| Format | Read | Stream | Write | Module |
|--------|------|--------|-------|--------|
| JSONL | ✅ | ✅ | ❌ | `HfDatasetsEx.Format.JSONL` |
| JSON | ✅ | ❌ | ❌ | `HfDatasetsEx.Format.JSON` |
| CSV | ✅ | ❌ | ❌ | `HfDatasetsEx.Format.CSV` |
| Parquet | ✅ | ✅* | ❌ | `HfDatasetsEx.Format.Parquet` |

*Parquet loads full file, batches during iteration

## Missing Input Formats

### P0 - Critical (Block Common Workflows)

#### Text Format

Simple text file where each line is an example.

```python
# Python packaged_modules/text/text.py
class TextBuilder(DatasetBuilder):
    # Reads .txt files, one line per example
    # Output: {"text": "line content"}
```

```elixir
# Proposed Elixir
defmodule HfDatasetsEx.Format.Text do
  @behaviour HfDatasetsEx.Format

  @impl true
  def parse(path, opts \\ []) do
    column = Keyword.get(opts, :column, "text")

    path
    |> File.stream!()
    |> Stream.map(&String.trim_trailing(&1, "\n"))
    |> Stream.with_index()
    |> Enum.map(fn {line, _idx} -> %{column => line} end)
  end

  @impl true
  def parse_stream(path, opts \\ []) do
    column = Keyword.get(opts, :column, "text")

    path
    |> File.stream!()
    |> Stream.map(fn line -> %{column => String.trim_trailing(line, "\n")} end)
  end
end
```

#### Arrow Format

Native Apache Arrow IPC format.

```python
# Python packaged_modules/arrow/arrow.py
class ArrowBuilder(DatasetBuilder):
    # Reads .arrow files (Arrow IPC format)
```

```elixir
# Proposed Elixir - requires adbc or arrow_ex
defmodule HfDatasetsEx.Format.Arrow do
  @behaviour HfDatasetsEx.Format

  @impl true
  def parse(path, _opts \\ []) do
    # Option 1: Use Explorer's Arrow support
    df = Explorer.DataFrame.from_arrow!(path)
    Explorer.DataFrame.to_rows(df)

    # Option 2: Use adbc library directly
  end

  @impl true
  def parse_stream(path, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 1000)
    # Stream Arrow record batches
  end
end
```

### P1 - High Priority

#### HDF5 Format

Hierarchical Data Format for large numerical datasets.

```python
# Python packaged_modules/hdf5/hdf5.py
class HDF5Builder(DatasetBuilder):
    # Reads .hdf5, .h5 files
```

```elixir
# Proposed Elixir - requires NIF wrapper
defmodule HfDatasetsEx.Format.HDF5 do
  @behaviour HfDatasetsEx.Format

  # Would need hdf5_ex or custom NIF
  @impl true
  def parse(path, opts \\ []) do
    key = Keyword.get(opts, :key, "/data")
    # Read HDF5 dataset at key
  end
end
```

#### XML Format

XML document parsing.

```python
# Python packaged_modules/xml/xml.py
class XMLBuilder(DatasetBuilder):
    # Reads .xml files with configurable structure
```

```elixir
# Proposed Elixir
defmodule HfDatasetsEx.Format.XML do
  @behaviour HfDatasetsEx.Format

  @impl true
  def parse(path, opts \\ []) do
    row_tag = Keyword.get(opts, :row_tag, "row")

    path
    |> File.read!()
    |> SweetXml.parse()
    |> SweetXml.xpath(~x"//#{row_tag}"l)
    |> Enum.map(&xml_to_map/1)
  end
end
```

### P2 - Medium Priority

#### SQL Format

Load data from SQL databases.

```python
# Python packaged_modules/sql/sql.py
class SQLBuilder(DatasetBuilder):
    # Reads from SQL databases via SQLAlchemy
```

```elixir
# Proposed Elixir
defmodule HfDatasetsEx.Format.SQL do
  @behaviour HfDatasetsEx.Format

  @spec from_query(Ecto.Repo.t(), String.t(), keyword()) :: [map()]
  def from_query(repo, sql, opts \\ []) do
    Ecto.Adapters.SQL.query!(repo, sql, Keyword.get(opts, :params, []))
    |> result_to_maps()
  end

  @spec from_table(Ecto.Repo.t(), String.t(), keyword()) :: [map()]
  def from_table(repo, table_name, opts \\ []) do
    from_query(repo, "SELECT * FROM #{table_name}", opts)
  end
end
```

#### WebDataset Format

Tar archive with samples as file sets.

```python
# Python packaged_modules/webdataset/webdataset.py
class WebDataset(DatasetBuilder):
    # Reads .tar files where samples are grouped by key
    # e.g., sample001.jpg, sample001.txt -> {"image": ..., "text": ...}
```

```elixir
# Proposed Elixir
defmodule HfDatasetsEx.Format.WebDataset do
  @behaviour HfDatasetsEx.Format

  @impl true
  def parse_stream(tar_path, _opts \\ []) do
    tar_path
    |> :erl_tar.extract({:binary, [:memory, :compressed]})
    |> group_by_sample_key()
    |> Stream.map(&combine_sample_files/1)
  end
end
```

### P3 - Low Priority (Specialized)

#### ImageFolder Format

Directory structure where subdirectories are class labels.

```python
# Python packaged_modules/imagefolder/imagefolder.py
# Structure:
# data/
#   train/
#     cat/
#       001.jpg
#     dog/
#       001.jpg
```

```elixir
# Proposed Elixir
defmodule HfDatasetsEx.Format.ImageFolder do
  @behaviour HfDatasetsEx.Format

  @impl true
  def parse(path, opts \\ []) do
    path
    |> Path.join("*/*")
    |> Path.wildcard()
    |> Enum.map(fn file_path ->
      label = file_path |> Path.dirname() |> Path.basename()
      %{
        "image" => %{"path" => file_path, "bytes" => File.read!(file_path)},
        "label" => label
      }
    end)
  end
end
```

#### AudioFolder Format

Same as ImageFolder but for audio files.

#### VideoFolder Format

Same as ImageFolder but for video files.

#### PdfFolder Format

Same as ImageFolder but for PDF files.

#### NiftiFolder Format

Same as ImageFolder but for NIfTI medical imaging files.

#### Spark Format

Load from Apache Spark DataFrames.

```python
# Python packaged_modules/spark/spark.py
class SparkBuilder(DatasetBuilder):
    # Converts Spark DataFrame to Dataset
```

```elixir
# Proposed Elixir - would need Spark interop
defmodule HfDatasetsEx.Format.Spark do
  # Unlikely to implement - Spark is JVM-based
  # Could use Arrow IPC as interchange format
end
```

## Missing Output Formats

### P0 - Critical

#### to_csv/2

```elixir
defmodule HfDatasetsEx.Export.CSV do
  @spec write(HfDatasetsEx.Dataset.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def write(%Dataset{} = dataset, path, opts \\ []) do
    delimiter = Keyword.get(opts, :delimiter, ",")
    headers = Dataset.column_names(dataset)

    rows =
      dataset.items
      |> Enum.map(fn item ->
        Enum.map(headers, fn h ->
          item |> Map.get(h, "") |> to_string()
        end)
      end)

    file = File.open!(path, [:write, :utf8])

    try do
      # Write header
      IO.write(file, Enum.join(headers, delimiter) <> "\n")

      # Write rows
      Enum.each(rows, fn row ->
        IO.write(file, Enum.join(row, delimiter) <> "\n")
      end)

      :ok
    after
      File.close(file)
    end
  end
end
```

#### to_json/2

```elixir
defmodule HfDatasetsEx.Export.JSON do
  @spec write(HfDatasetsEx.Dataset.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def write(%Dataset{} = dataset, path, opts \\ []) do
    orient = Keyword.get(opts, :orient, :records)

    content = case orient do
      :records ->
        dataset.items |> Jason.encode!(pretty: true)
      :columns ->
        dataset.items
        |> to_column_format()
        |> Jason.encode!(pretty: true)
    end

    File.write(path, content)
  end

  @spec write_jsonl(HfDatasetsEx.Dataset.t(), Path.t()) :: :ok | {:error, term()}
  def write_jsonl(%Dataset{} = dataset, path) do
    file = File.open!(path, [:write, :utf8])

    try do
      Enum.each(dataset.items, fn item ->
        IO.write(file, Jason.encode!(item) <> "\n")
      end)
      :ok
    after
      File.close(file)
    end
  end
end
```

#### to_parquet/2

```elixir
defmodule HfDatasetsEx.Export.Parquet do
  @spec write(HfDatasetsEx.Dataset.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def write(%Dataset{} = dataset, path, opts \\ []) do
    compression = Keyword.get(opts, :compression, :snappy)

    # Convert to Explorer DataFrame
    df = dataset.items
         |> Explorer.DataFrame.new()

    # Write to Parquet
    Explorer.DataFrame.to_parquet(df, path, compression: compression)
  end
end
```

### P1 - High Priority

#### to_arrow/2

```elixir
defmodule HfDatasetsEx.Export.Arrow do
  @spec write(HfDatasetsEx.Dataset.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def write(%Dataset{} = dataset, path, _opts \\ []) do
    df = Explorer.DataFrame.new(dataset.items)
    Explorer.DataFrame.to_ipc(df, path)
  end
end
```

#### save_to_disk/2

Saves dataset in HuggingFace's disk format (Arrow + metadata).

```elixir
defmodule HfDatasetsEx.Export.Disk do
  @spec save(HfDatasetsEx.Dataset.t(), Path.t()) :: :ok | {:error, term()}
  def save(%Dataset{} = dataset, path) do
    # Create directory structure
    File.mkdir_p!(path)

    # Save Arrow data
    data_path = Path.join(path, "data-00000-of-00001.arrow")
    Export.Arrow.write(dataset, data_path)

    # Save dataset_info.json
    info_path = Path.join(path, "dataset_info.json")
    info = %{
      features: Features.to_json(dataset.features),
      num_rows: Dataset.num_items(dataset),
      size_in_bytes: File.stat!(data_path).size
    }
    File.write!(info_path, Jason.encode!(info, pretty: true))

    # Save state.json
    state_path = Path.join(path, "state.json")
    state = %{_data_files: [%{filename: "data-00000-of-00001.arrow"}]}
    File.write!(state_path, Jason.encode!(state))

    :ok
  end
end
```

### P2 - Medium Priority

#### to_sql/4

```elixir
defmodule HfDatasetsEx.Export.SQL do
  @spec write(HfDatasetsEx.Dataset.t(), atom(), String.t(), keyword()) :: :ok | {:error, term()}
  def write(%Dataset{} = dataset, repo, table_name, opts \\ []) do
    if_exists = Keyword.get(opts, :if_exists, :fail)

    # Handle existing table
    case if_exists do
      :fail -> :ok  # Will fail naturally if exists
      :replace -> Ecto.Adapters.SQL.query!(repo, "DROP TABLE IF EXISTS #{table_name}")
      :append -> :ok
    end

    # Create table and insert
    # This would need schema inference
  end
end
```

## Format Registry Updates

```elixir
# Update lib/dataset_manager/format.ex
defmodule HfDatasetsEx.Format do
  @extension_map %{
    ".jsonl" => HfDatasetsEx.Format.JSONL,
    ".ndjson" => HfDatasetsEx.Format.JSONL,
    ".json" => HfDatasetsEx.Format.JSON,
    ".csv" => HfDatasetsEx.Format.CSV,
    ".tsv" => {HfDatasetsEx.Format.CSV, sep: "\t"},
    ".parquet" => HfDatasetsEx.Format.Parquet,
    ".txt" => HfDatasetsEx.Format.Text,       # Add
    ".arrow" => HfDatasetsEx.Format.Arrow,     # Add
    ".xml" => HfDatasetsEx.Format.XML,         # Add
    ".h5" => HfDatasetsEx.Format.HDF5,         # Add
    ".hdf5" => HfDatasetsEx.Format.HDF5,       # Add
    ".tar" => HfDatasetsEx.Format.WebDataset   # Add
  }
end
```

## Files to Create/Modify

### New Input Format Modules

| File | Priority |
|------|----------|
| `lib/dataset_manager/format/text.ex` | P0 |
| `lib/dataset_manager/format/arrow.ex` | P0 |
| `lib/dataset_manager/format/xml.ex` | P1 |
| `lib/dataset_manager/format/hdf5.ex` | P2 |
| `lib/dataset_manager/format/sql.ex` | P2 |
| `lib/dataset_manager/format/webdataset.ex` | P2 |
| `lib/dataset_manager/format/imagefolder.ex` | P3 |
| `lib/dataset_manager/format/audiofolder.ex` | P3 |

### New Export Modules

| File | Priority |
|------|----------|
| `lib/dataset_manager/export.ex` | P0 |
| `lib/dataset_manager/export/csv.ex` | P0 |
| `lib/dataset_manager/export/json.ex` | P0 |
| `lib/dataset_manager/export/parquet.ex` | P0 |
| `lib/dataset_manager/export/arrow.ex` | P1 |
| `lib/dataset_manager/export/disk.ex` | P1 |
| `lib/dataset_manager/export/sql.ex` | P2 |

## Dependencies

| Feature | Dependency | Hex Package |
|---------|------------|-------------|
| Arrow I/O | Explorer | ✅ Already have |
| XML | SweetXml | `sweet_xml` |
| HDF5 | Custom NIF | TBD |
| SQL | Ecto | `ecto_sql` |
| WebDataset | Erlang tar | ✅ Built-in |

## Testing Requirements

Each format needs:
1. Parse test with sample file
2. Round-trip test (read → write → read)
3. Edge cases (empty, large, special characters)
4. Streaming test where applicable
5. Error handling tests (corrupted files, missing files)
