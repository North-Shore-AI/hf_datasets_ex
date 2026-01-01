# Implementation Prompt: Export Formats

## Priority: P0 (Critical)

## Objective

Implement export functionality (`to_csv/2`, `to_json/2`, `to_parquet/2`, `to_jsonl/2`) for the `HfDatasetsEx.Dataset` module.

## Required Reading

Before starting, read these files completely:

```
lib/dataset_manager/dataset.ex
lib/dataset_manager/format/jsonl.ex
lib/dataset_manager/format/json.ex
lib/dataset_manager/format/csv.ex
lib/dataset_manager/format/parquet.ex
mix.exs (for dependencies)
test/dataset_manager/dataset_ops_test.exs (for testing patterns)
docs/20251231/gap_analysis/03_io_formats.md
```

## Context

The Elixir port `hf_datasets_ex` can read CSV, JSON, JSONL, and Parquet formats but cannot write any of them. The Python `datasets` library provides `to_csv()`, `to_json()`, `to_parquet()` methods on the `Dataset` class.

Current dependencies:
- `jason` ~> 1.4 (JSON encoding)
- `explorer` ~> 0.11.1 (DataFrames, Parquet support)

## Implementation Requirements

### 1. Create Export Module

Create `lib/dataset_manager/export.ex`:

```elixir
defmodule HfDatasetsEx.Export do
  @moduledoc """
  Export functionality for datasets.
  """

  alias HfDatasetsEx.Dataset

  @doc """
  Export dataset to CSV file.
  """
  @spec to_csv(Dataset.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def to_csv(%Dataset{} = dataset, path, opts \\ [])

  @doc """
  Export dataset to JSON file.
  """
  @spec to_json(Dataset.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def to_json(%Dataset{} = dataset, path, opts \\ [])

  @doc """
  Export dataset to JSONL file.
  """
  @spec to_jsonl(Dataset.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def to_jsonl(%Dataset{} = dataset, path, opts \\ [])

  @doc """
  Export dataset to Parquet file.
  """
  @spec to_parquet(Dataset.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def to_parquet(%Dataset{} = dataset, path, opts \\ [])
end
```

### 2. Add Delegate Functions to Dataset

Add to `lib/dataset_manager/dataset.ex`:

```elixir
defdelegate to_csv(dataset, path, opts \\ []), to: HfDatasetsEx.Export
defdelegate to_json(dataset, path, opts \\ []), to: HfDatasetsEx.Export
defdelegate to_jsonl(dataset, path, opts \\ []), to: HfDatasetsEx.Export
defdelegate to_parquet(dataset, path, opts \\ []), to: HfDatasetsEx.Export
```

### 3. Implementation Details

#### to_csv/3

Options:
- `:delimiter` - Field delimiter (default: `","`)
- `:headers` - Include headers (default: `true`)
- `:columns` - Specific columns to export (default: all)

```elixir
def to_csv(%Dataset{items: items} = dataset, path, opts) do
  delimiter = Keyword.get(opts, :delimiter, ",")
  include_headers = Keyword.get(opts, :headers, true)
  columns = Keyword.get(opts, :columns) || Dataset.column_names(dataset)

  file = File.open!(path, [:write, :utf8])

  try do
    if include_headers do
      IO.write(file, Enum.join(columns, delimiter) <> "\n")
    end

    Enum.each(items, fn item ->
      row = Enum.map(columns, fn col ->
        value = Map.get(item, col, "")
        escape_csv_value(value, delimiter)
      end)
      IO.write(file, Enum.join(row, delimiter) <> "\n")
    end)

    :ok
  after
    File.close(file)
  end
end

defp escape_csv_value(value, delimiter) when is_binary(value) do
  needs_quoting = String.contains?(value, [delimiter, "\"", "\n", "\r"])

  if needs_quoting do
    "\"" <> String.replace(value, "\"", "\"\"") <> "\""
  else
    value
  end
end

defp escape_csv_value(value, _delimiter), do: to_string(value)
```

#### to_json/3

Options:
- `:orient` - `:records` (list of objects) or `:columns` (column-oriented)
- `:pretty` - Pretty print (default: `false`)

```elixir
def to_json(%Dataset{items: items}, path, opts) do
  orient = Keyword.get(opts, :orient, :records)
  pretty = Keyword.get(opts, :pretty, false)

  content = case orient do
    :records -> items
    :columns -> to_column_format(items)
  end

  json_opts = if pretty, do: [pretty: true], else: []
  File.write(path, Jason.encode!(content, json_opts))
end

defp to_column_format(items) when items == [], do: %{}
defp to_column_format([first | _] = items) do
  keys = Map.keys(first)

  Map.new(keys, fn key ->
    {key, Enum.map(items, &Map.get(&1, key))}
  end)
end
```

#### to_jsonl/3

```elixir
def to_jsonl(%Dataset{items: items}, path, _opts) do
  file = File.open!(path, [:write, :utf8])

  try do
    Enum.each(items, fn item ->
      IO.write(file, Jason.encode!(item) <> "\n")
    end)
    :ok
  after
    File.close(file)
  end
end
```

#### to_parquet/3

Options:
- `:compression` - `:snappy`, `:gzip`, `:zstd`, `:none` (default: `:snappy`)

```elixir
def to_parquet(%Dataset{items: items}, path, opts) do
  compression = Keyword.get(opts, :compression, :snappy)

  df = Explorer.DataFrame.new(items)
  Explorer.DataFrame.to_parquet(df, path, compression: compression)
end
```

## TDD Approach

### Step 1: Write Tests First

Create `test/dataset_manager/export_test.exs`:

```elixir
defmodule HfDatasetsEx.ExportTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.{Dataset, Export}

  @temp_dir System.tmp_dir!()

  setup do
    dataset = Dataset.from_list([
      %{"name" => "Alice", "age" => 30, "city" => "NYC"},
      %{"name" => "Bob", "age" => 25, "city" => "LA"}
    ])

    {:ok, dataset: dataset}
  end

  describe "to_csv/3" do
    test "exports basic dataset to CSV", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_#{:rand.uniform(100000)}.csv")

      assert :ok = Export.to_csv(dataset, path)
      assert File.exists?(path)

      content = File.read!(path)
      lines = String.split(content, "\n", trim: true)

      assert length(lines) == 3  # header + 2 rows
      assert hd(lines) =~ "name"
      assert hd(lines) =~ "age"
    end

    test "handles values with commas", %{dataset: _dataset} do
      ds = Dataset.from_list([%{"text" => "hello, world"}])
      path = Path.join(@temp_dir, "test_comma_#{:rand.uniform(100000)}.csv")

      assert :ok = Export.to_csv(ds, path)

      content = File.read!(path)
      assert content =~ "\"hello, world\""
    end

    test "handles values with quotes", %{dataset: _dataset} do
      ds = Dataset.from_list([%{"text" => "say \"hello\""}])
      path = Path.join(@temp_dir, "test_quote_#{:rand.uniform(100000)}.csv")

      assert :ok = Export.to_csv(ds, path)

      content = File.read!(path)
      assert content =~ "\"say \"\"hello\"\"\""
    end

    test "respects :headers option", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_noheader_#{:rand.uniform(100000)}.csv")

      assert :ok = Export.to_csv(dataset, path, headers: false)

      content = File.read!(path)
      lines = String.split(content, "\n", trim: true)

      assert length(lines) == 2  # no header
    end

    test "respects :columns option", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_cols_#{:rand.uniform(100000)}.csv")

      assert :ok = Export.to_csv(dataset, path, columns: ["name", "age"])

      content = File.read!(path)
      refute content =~ "city"
    end
  end

  describe "to_json/3" do
    test "exports to JSON records format", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_#{:rand.uniform(100000)}.json")

      assert :ok = Export.to_json(dataset, path)
      assert File.exists?(path)

      {:ok, data} = Jason.decode(File.read!(path))
      assert is_list(data)
      assert length(data) == 2
    end

    test "exports to JSON columns format", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_cols_#{:rand.uniform(100000)}.json")

      assert :ok = Export.to_json(dataset, path, orient: :columns)

      {:ok, data} = Jason.decode(File.read!(path))
      assert is_map(data)
      assert Map.has_key?(data, "name")
      assert is_list(data["name"])
    end
  end

  describe "to_jsonl/3" do
    test "exports to JSONL format", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_#{:rand.uniform(100000)}.jsonl")

      assert :ok = Export.to_jsonl(dataset, path)
      assert File.exists?(path)

      lines = path |> File.read!() |> String.split("\n", trim: true)
      assert length(lines) == 2

      assert {:ok, _} = Jason.decode(hd(lines))
    end
  end

  describe "to_parquet/3" do
    test "exports to Parquet format", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_#{:rand.uniform(100000)}.parquet")

      assert :ok = Export.to_parquet(dataset, path)
      assert File.exists?(path)

      # Verify by reading back
      df = Explorer.DataFrame.from_parquet!(path)
      assert Explorer.DataFrame.n_rows(df) == 2
    end
  end

  describe "round-trip" do
    test "CSV round-trip preserves data", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_rt_#{:rand.uniform(100000)}.csv")

      :ok = Export.to_csv(dataset, path)
      {:ok, loaded} = HfDatasetsEx.Loader.load_from_file(path)

      assert Dataset.num_items(loaded) == Dataset.num_items(dataset)
    end

    test "JSONL round-trip preserves data", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_rt_#{:rand.uniform(100000)}.jsonl")

      :ok = Export.to_jsonl(dataset, path)
      {:ok, loaded} = HfDatasetsEx.Loader.load_from_file(path)

      assert Dataset.num_items(loaded) == Dataset.num_items(dataset)
    end

    test "Parquet round-trip preserves data", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_rt_#{:rand.uniform(100000)}.parquet")

      :ok = Export.to_parquet(dataset, path)
      {:ok, loaded} = HfDatasetsEx.Loader.load_from_file(path)

      assert Dataset.num_items(loaded) == Dataset.num_items(dataset)
    end
  end
end
```

### Step 2: Run Tests (They Should Fail)

```bash
mix test test/dataset_manager/export_test.exs
```

### Step 3: Implement Until Tests Pass

### Step 4: Quality Checks

```bash
mix format
mix credo --strict
mix dialyzer
mix test
```

## Acceptance Criteria

- [ ] All tests pass
- [ ] `mix format` produces no changes
- [ ] `mix credo --strict` reports no issues
- [ ] `mix dialyzer` reports no errors
- [ ] `mix compile --warnings-as-errors` succeeds
- [ ] Documentation with `@doc` and `@spec` for all public functions
- [ ] Round-trip tests (export → import) verify data integrity

## Files to Create/Modify

| File | Action |
|------|--------|
| `lib/dataset_manager/export.ex` | Create |
| `lib/dataset_manager/dataset.ex` | Add delegates |
| `test/dataset_manager/export_test.exs` | Create |

## Edge Cases to Handle

1. Empty dataset
2. Dataset with nil values
3. Dataset with nested maps (flatten or error?)
4. Very large datasets (streaming?)
5. Unicode characters
6. Binary data in columns
7. File path doesn't exist (create parent dirs)
8. File already exists (overwrite by default)
