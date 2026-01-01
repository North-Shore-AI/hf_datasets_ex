# Implementation Prompt: Dataset Creation Methods

## Priority: P0 (Critical)

## Objective

Implement missing dataset creation methods: `from_generator/2`, `from_csv/2`, `from_json/2`, `from_parquet/2`, and `from_text/2`.

## Required Reading

Before starting, read these files completely:

```
lib/dataset_manager/dataset.ex
lib/dataset_manager/iterable_dataset.ex
lib/dataset_manager/format/jsonl.ex
lib/dataset_manager/format/json.ex
lib/dataset_manager/format/csv.ex
lib/dataset_manager/format/parquet.ex
lib/dataset_manager/loader.ex
docs/20251231/gap_analysis/01_core_dataset_methods.md
```

## Context

The Python `datasets` library provides convenient `Dataset.from_*` class methods:
- `from_generator(generator_fn)` - Create from a generator function (lazy)
- `from_csv(path)` - Create from CSV file
- `from_json(path)` - Create from JSON file
- `from_parquet(path)` - Create from Parquet file
- `from_text(path)` - Create from text file (one line per example)

The Elixir port has:
- `from_list/2` - Create from list of maps (exists)
- `from_dataframe/2` - Create from Explorer DataFrame (exists)
- Format parsers exist but aren't exposed as `from_*` methods

## Implementation Requirements

### 1. Add from_generator/2

```elixir
@doc """
Create a dataset from a generator function.

The generator should return an Enumerable that yields maps.

## Options

  * `:eager` - Immediately materialize (default: false, returns IterableDataset)
  * `:features` - Feature schema
  * `:name` - Dataset name

## Examples

    # Returns IterableDataset (lazy)
    Dataset.from_generator(fn ->
      Stream.repeatedly(fn -> %{"x" => :rand.uniform()} end)
      |> Stream.take(100)
    end)

    # Returns Dataset (eager)
    Dataset.from_generator(
      fn -> 1..100 |> Stream.map(&%{"x" => &1}) end,
      eager: true
    )

"""
@spec from_generator((() -> Enumerable.t()), keyword()) :: IterableDataset.t() | t()
def from_generator(generator_fn, opts \\ []) when is_function(generator_fn, 0) do
  eager = Keyword.get(opts, :eager, false)
  name = Keyword.get(opts, :name, "generated")
  features = Keyword.get(opts, :features)

  if eager do
    items = generator_fn.() |> Enum.to_list()
    from_list(items, name: name, features: features)
  else
    stream = Stream.resource(
      fn -> generator_fn.() end,
      fn enum ->
        case Enum.take(enum, 1) do
          [] -> {:halt, enum}
          [item] ->
            # Advance the enumerable
            rest = Stream.drop(enum, 1)
            {[item], rest}
        end
      end,
      fn _enum -> :ok end
    )

    IterableDataset.from_stream(stream, name: name, features: features)
  end
end
```

Actually, simpler approach:

```elixir
@spec from_generator((() -> Enumerable.t()), keyword()) :: IterableDataset.t() | t()
def from_generator(generator_fn, opts \\ []) when is_function(generator_fn, 0) do
  eager = Keyword.get(opts, :eager, false)
  name = Keyword.get(opts, :name, "generated")
  features = Keyword.get(opts, :features)

  stream = Stream.flat_map([nil], fn _ -> generator_fn.() end)

  if eager do
    items = Enum.to_list(stream)
    from_list(items, name: name, features: features)
  else
    IterableDataset.from_stream(stream, name: name, features: features)
  end
end
```

### 2. Add from_csv/2

```elixir
@doc """
Create a dataset from a CSV file.

## Options

  * `:delimiter` - Field delimiter (default: ",")
  * `:headers` - Use first row as headers (default: true)
  * `:features` - Feature schema
  * `:name` - Dataset name (default: filename)

## Examples

    Dataset.from_csv("/path/to/data.csv")
    Dataset.from_csv("/path/to/data.tsv", delimiter: "\\t")

"""
@spec from_csv(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
def from_csv(path, opts \\ []) do
  name = Keyword.get(opts, :name, Path.basename(path, ".csv"))
  features = Keyword.get(opts, :features)

  with {:ok, items} <- HfDatasetsEx.Format.CSV.parse(path, opts) do
    dataset = from_list(items, name: name, features: features)
    {:ok, dataset}
  end
end
```

### 3. Add from_json/2

```elixir
@doc """
Create a dataset from a JSON file.

Supports both single JSON array and JSONL (one JSON object per line).

## Options

  * `:features` - Feature schema
  * `:name` - Dataset name

## Examples

    # JSON array
    Dataset.from_json("/path/to/data.json")

    # JSONL (auto-detected by .jsonl extension)
    Dataset.from_json("/path/to/data.jsonl")

"""
@spec from_json(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
def from_json(path, opts \\ []) do
  name = Keyword.get(opts, :name, Path.basename(path) |> Path.rootname())
  features = Keyword.get(opts, :features)

  parser = if String.ends_with?(path, ".jsonl") or String.ends_with?(path, ".ndjson") do
    HfDatasetsEx.Format.JSONL
  else
    HfDatasetsEx.Format.JSON
  end

  with {:ok, items} <- parser.parse(path, opts) do
    dataset = from_list(items, name: name, features: features)
    {:ok, dataset}
  end
end
```

### 4. Add from_parquet/2

```elixir
@doc """
Create a dataset from a Parquet file.

## Options

  * `:columns` - Select specific columns
  * `:features` - Feature schema
  * `:name` - Dataset name

## Examples

    Dataset.from_parquet("/path/to/data.parquet")
    Dataset.from_parquet("/path/to/data.parquet", columns: ["id", "text"])

"""
@spec from_parquet(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
def from_parquet(path, opts \\ []) do
  name = Keyword.get(opts, :name, Path.basename(path, ".parquet"))
  columns = Keyword.get(opts, :columns)
  features = Keyword.get(opts, :features)

  try do
    df = Explorer.DataFrame.from_parquet!(path)

    df = if columns do
      Explorer.DataFrame.select(df, columns)
    else
      df
    end

    items = Explorer.DataFrame.to_rows(df)
    dataset = from_list(items, name: name, features: features)
    {:ok, dataset}
  rescue
    e -> {:error, e}
  end
end
```

### 5. Add from_text/2

```elixir
@doc """
Create a dataset from a text file (one line per example).

## Options

  * `:column` - Column name for text (default: "text")
  * `:strip` - Strip whitespace from lines (default: true)
  * `:skip_empty` - Skip empty lines (default: true)
  * `:features` - Feature schema
  * `:name` - Dataset name

## Examples

    Dataset.from_text("/path/to/data.txt")
    Dataset.from_text("/path/to/data.txt", column: "content")

"""
@spec from_text(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
def from_text(path, opts \\ []) do
  name = Keyword.get(opts, :name, Path.basename(path, ".txt"))
  column = Keyword.get(opts, :column, "text")
  strip = Keyword.get(opts, :strip, true)
  skip_empty = Keyword.get(opts, :skip_empty, true)
  features = Keyword.get(opts, :features)

  try do
    items =
      path
      |> File.stream!()
      |> Stream.map(fn line ->
        if strip, do: String.trim(line), else: String.trim_trailing(line, "\n")
      end)
      |> Stream.reject(fn line -> skip_empty and line == "" end)
      |> Enum.map(fn line -> %{column => line} end)

    dataset = from_list(items, name: name, features: features)
    {:ok, dataset}
  rescue
    e -> {:error, e}
  end
end
```

### 6. Add Bang Versions

```elixir
@doc """
Same as `from_csv/2` but raises on error.
"""
@spec from_csv!(Path.t(), keyword()) :: t()
def from_csv!(path, opts \\ []) do
  case from_csv(path, opts) do
    {:ok, dataset} -> dataset
    {:error, error} -> raise "Failed to load CSV: #{inspect(error)}"
  end
end

# Similar for from_json!, from_parquet!, from_text!
```

## TDD Approach

### Step 1: Write Tests First

Create `test/dataset_manager/dataset_creation_test.exs`:

```elixir
defmodule HfDatasetsEx.DatasetCreationTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.{Dataset, IterableDataset}

  @fixtures_dir Path.join(__DIR__, "../fixtures")

  setup_all do
    # Create test fixtures
    File.mkdir_p!(@fixtures_dir)

    # CSV
    File.write!(Path.join(@fixtures_dir, "test.csv"), """
    name,age
    Alice,30
    Bob,25
    """)

    # JSON
    File.write!(Path.join(@fixtures_dir, "test.json"), """
    [{"name": "Alice", "age": 30}, {"name": "Bob", "age": 25}]
    """)

    # JSONL
    File.write!(Path.join(@fixtures_dir, "test.jsonl"), """
    {"name": "Alice", "age": 30}
    {"name": "Bob", "age": 25}
    """)

    # Text
    File.write!(Path.join(@fixtures_dir, "test.txt"), """
    Hello world
    How are you
    """)

    on_exit(fn -> File.rm_rf!(@fixtures_dir) end)

    :ok
  end

  describe "from_generator/2" do
    test "creates IterableDataset by default" do
      result = Dataset.from_generator(fn ->
        1..3 |> Stream.map(&%{"x" => &1})
      end)

      assert %IterableDataset{} = result
    end

    test "creates eager Dataset with :eager option" do
      result = Dataset.from_generator(
        fn -> 1..3 |> Stream.map(&%{"x" => &1}) end,
        eager: true
      )

      assert %Dataset{} = result
      assert Dataset.num_items(result) == 3
    end

    test "generator is evaluated lazily" do
      counter = :counters.new(1, [:atomics])

      result = Dataset.from_generator(fn ->
        Stream.map(1..10, fn x ->
          :counters.add(counter, 1, 1)
          %{"x" => x}
        end)
      end)

      # Generator not called yet
      assert :counters.get(counter, 1) == 0

      # Take 3 items
      _ = result |> Enum.take(3)

      # Only 3 items evaluated
      assert :counters.get(counter, 1) == 3
    end
  end

  describe "from_csv/2" do
    test "loads CSV file" do
      path = Path.join(@fixtures_dir, "test.csv")

      assert {:ok, dataset} = Dataset.from_csv(path)
      assert Dataset.num_items(dataset) == 2
      assert Dataset.column_names(dataset) == ["age", "name"]
    end

    test "handles missing file" do
      assert {:error, _} = Dataset.from_csv("/nonexistent.csv")
    end

    test "from_csv! raises on error" do
      assert_raise RuntimeError, fn ->
        Dataset.from_csv!("/nonexistent.csv")
      end
    end
  end

  describe "from_json/2" do
    test "loads JSON array file" do
      path = Path.join(@fixtures_dir, "test.json")

      assert {:ok, dataset} = Dataset.from_json(path)
      assert Dataset.num_items(dataset) == 2
    end

    test "loads JSONL file" do
      path = Path.join(@fixtures_dir, "test.jsonl")

      assert {:ok, dataset} = Dataset.from_json(path)
      assert Dataset.num_items(dataset) == 2
    end
  end

  describe "from_parquet/2" do
    setup do
      path = Path.join(@fixtures_dir, "test.parquet")

      df = Explorer.DataFrame.new(%{
        "name" => ["Alice", "Bob"],
        "age" => [30, 25]
      })
      Explorer.DataFrame.to_parquet(df, path)

      {:ok, path: path}
    end

    test "loads Parquet file", %{path: path} do
      assert {:ok, dataset} = Dataset.from_parquet(path)
      assert Dataset.num_items(dataset) == 2
    end

    test "selects specific columns", %{path: path} do
      assert {:ok, dataset} = Dataset.from_parquet(path, columns: ["name"])
      assert Dataset.column_names(dataset) == ["name"]
    end
  end

  describe "from_text/2" do
    test "loads text file" do
      path = Path.join(@fixtures_dir, "test.txt")

      assert {:ok, dataset} = Dataset.from_text(path)
      assert Dataset.num_items(dataset) == 2

      [first | _] = dataset.items
      assert Map.has_key?(first, "text")
    end

    test "uses custom column name" do
      path = Path.join(@fixtures_dir, "test.txt")

      assert {:ok, dataset} = Dataset.from_text(path, column: "content")

      [first | _] = dataset.items
      assert Map.has_key?(first, "content")
    end

    test "strips whitespace by default" do
      path = Path.join(@fixtures_dir, "test.txt")

      assert {:ok, dataset} = Dataset.from_text(path)

      [first | _] = dataset.items
      refute String.ends_with?(first["text"], "\n")
    end
  end
end
```

### Step 2: Run Tests (They Should Fail)

```bash
mix test test/dataset_manager/dataset_creation_test.exs
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
- [ ] `from_generator` returns `IterableDataset` by default
- [ ] Bang versions raise on error
- [ ] All methods have `@doc` and `@spec`

## Files to Modify

| File | Action |
|------|--------|
| `lib/dataset_manager/dataset.ex` | Add from_* functions |
| `test/dataset_manager/dataset_creation_test.exs` | Create |
| `test/fixtures/` | Create test files |

## Edge Cases to Handle

1. Empty files
2. Files with only headers (CSV)
3. Invalid JSON syntax
4. Unicode content
5. Very large files (streaming consideration)
6. Generator that raises errors
7. Infinite generators with `from_generator`
