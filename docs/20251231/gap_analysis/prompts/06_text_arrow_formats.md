# Implementation Prompt: Text and Arrow I/O Formats

## Priority: P1 (High)

## Objective

Implement text file and Arrow IPC format support for reading and writing datasets.

## Required Reading

Before starting, read these files completely:

```
lib/dataset_manager/format.ex
lib/dataset_manager/format/jsonl.ex
lib/dataset_manager/format/parquet.ex
mix.exs
docs/20251231/gap_analysis/03_io_formats.md
```

## Context

The Python `datasets` library supports:
- `.txt` files - One line per example
- `.arrow` files - Native Arrow IPC format

These are commonly used formats:
- Text files for simple NLP datasets (one sentence per line)
- Arrow for efficient dataset storage and interchange

The Elixir port already uses Explorer which has Arrow support.

## Implementation Requirements

### 1. Text Format Parser

Create `lib/dataset_manager/format/text.ex`:

```elixir
defmodule HfDatasetsEx.Format.Text do
  @moduledoc """
  Parser for plain text files.

  Each line becomes a row with a single "text" column.
  """

  @behaviour HfDatasetsEx.Format

  @type options :: [
    column: String.t(),
    strip: boolean(),
    skip_empty: boolean()
  ]

  @impl true
  @spec parse(Path.t(), options()) :: {:ok, [map()]} | {:error, term()}
  def parse(path, opts \\ []) do
    column = Keyword.get(opts, :column, "text")
    strip = Keyword.get(opts, :strip, true)
    skip_empty = Keyword.get(opts, :skip_empty, true)

    try do
      items =
        path
        |> File.stream!([:utf8])
        |> Stream.map(fn line ->
          if strip do
            String.trim(line)
          else
            String.trim_trailing(line, "\n")
          end
        end)
        |> maybe_skip_empty(skip_empty)
        |> Enum.map(fn line -> %{column => line} end)

      {:ok, items}
    rescue
      e -> {:error, e}
    end
  end

  @impl true
  @spec parse_stream(Path.t(), options()) :: Enumerable.t()
  def parse_stream(path, opts \\ []) do
    column = Keyword.get(opts, :column, "text")
    strip = Keyword.get(opts, :strip, true)
    skip_empty = Keyword.get(opts, :skip_empty, true)

    path
    |> File.stream!([:utf8])
    |> Stream.map(fn line ->
      if strip, do: String.trim(line), else: String.trim_trailing(line, "\n")
    end)
    |> maybe_skip_empty(skip_empty)
    |> Stream.map(fn line -> %{column => line} end)
  end

  defp maybe_skip_empty(stream, true) do
    Stream.reject(stream, &(&1 == ""))
  end

  defp maybe_skip_empty(stream, false), do: stream
end
```

### 2. Text Format Writer

Create `lib/dataset_manager/export/text.ex`:

```elixir
defmodule HfDatasetsEx.Export.Text do
  @moduledoc """
  Export dataset to plain text file.
  """

  alias HfDatasetsEx.Dataset

  @type options :: [
    column: String.t(),
    append_newline: boolean()
  ]

  @spec write(Dataset.t(), Path.t(), options()) :: :ok | {:error, term()}
  def write(%Dataset{items: items}, path, opts \\ []) do
    column = Keyword.get(opts, :column, "text")
    append_newline = Keyword.get(opts, :append_newline, true)

    file = File.open!(path, [:write, :utf8])

    try do
      Enum.each(items, fn item ->
        text = Map.get(item, column, "")
        if append_newline do
          IO.write(file, text <> "\n")
        else
          IO.write(file, text)
        end
      end)

      :ok
    after
      File.close(file)
    end
  end
end
```

### 3. Arrow Format Parser

Create `lib/dataset_manager/format/arrow.ex`:

```elixir
defmodule HfDatasetsEx.Format.Arrow do
  @moduledoc """
  Parser for Apache Arrow IPC format files.

  Uses Explorer's Arrow support.
  """

  @behaviour HfDatasetsEx.Format

  @type options :: [
    columns: [String.t()] | nil
  ]

  @impl true
  @spec parse(Path.t(), options()) :: {:ok, [map()]} | {:error, term()}
  def parse(path, opts \\ []) do
    columns = Keyword.get(opts, :columns)

    try do
      df = Explorer.DataFrame.from_ipc!(path)

      df = if columns do
        Explorer.DataFrame.select(df, columns)
      else
        df
      end

      items = Explorer.DataFrame.to_rows(df)
      {:ok, items}
    rescue
      e -> {:error, e}
    end
  end

  @impl true
  @spec parse_stream(Path.t(), options()) :: Enumerable.t()
  def parse_stream(path, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 10_000)

    # Arrow IPC doesn't support true streaming in Explorer
    # Load and chunk
    {:ok, items} = parse(path, opts)

    Stream.chunk_every(items, batch_size)
    |> Stream.flat_map(& &1)
  end

  @doc """
  Check if file is a valid Arrow IPC file.
  """
  @spec valid?(Path.t()) :: boolean()
  def valid?(path) do
    case File.read(path) do
      {:ok, data} ->
        # Arrow IPC magic bytes: "ARROW1" at start or end
        String.starts_with?(data, "ARROW1") or
        String.ends_with?(data, <<255, 255, 255, 255, 0, 0, 0, 0>>)
      _ ->
        false
    end
  end
end
```

### 4. Arrow Format Writer

Create `lib/dataset_manager/export/arrow.ex`:

```elixir
defmodule HfDatasetsEx.Export.Arrow do
  @moduledoc """
  Export dataset to Apache Arrow IPC format.
  """

  alias HfDatasetsEx.Dataset

  @type options :: [
    compression: :lz4 | :zstd | nil
  ]

  @spec write(Dataset.t(), Path.t(), options()) :: :ok | {:error, term()}
  def write(%Dataset{items: items}, path, opts \\ []) do
    compression = Keyword.get(opts, :compression)

    try do
      df = Explorer.DataFrame.new(items)

      ipc_opts = if compression do
        [compression: compression]
      else
        []
      end

      Explorer.DataFrame.to_ipc(df, path, ipc_opts)
      :ok
    rescue
      e -> {:error, e}
    end
  end

  @doc """
  Write dataset to Arrow IPC stream format (for streaming).
  """
  @spec write_stream(Dataset.t(), Path.t(), options()) :: :ok | {:error, term()}
  def write_stream(%Dataset{items: items}, path, _opts \\ []) do
    try do
      df = Explorer.DataFrame.new(items)
      Explorer.DataFrame.to_ipc_stream(df, path)
      :ok
    rescue
      e -> {:error, e}
    end
  end
end
```

### 5. Update Format Registry

Update `lib/dataset_manager/format.ex`:

```elixir
defmodule HfDatasetsEx.Format do
  @moduledoc """
  Format detection and parser registry.
  """

  @callback parse(Path.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback parse_stream(Path.t(), keyword()) :: Enumerable.t()

  @optional_callbacks [parse_stream: 2]

  @extension_map %{
    ".jsonl" => HfDatasetsEx.Format.JSONL,
    ".ndjson" => HfDatasetsEx.Format.JSONL,
    ".json" => HfDatasetsEx.Format.JSON,
    ".csv" => HfDatasetsEx.Format.CSV,
    ".tsv" => {HfDatasetsEx.Format.CSV, [delimiter: "\t"]},
    ".parquet" => HfDatasetsEx.Format.Parquet,
    ".txt" => HfDatasetsEx.Format.Text,      # Add
    ".text" => HfDatasetsEx.Format.Text,     # Add
    ".arrow" => HfDatasetsEx.Format.Arrow,   # Add
    ".ipc" => HfDatasetsEx.Format.Arrow      # Add
  }

  @doc """
  Detect format from file extension.
  """
  @spec detect(Path.t()) :: {:ok, module(), keyword()} | {:error, :unknown_format}
  def detect(path) do
    ext = Path.extname(path) |> String.downcase()

    case Map.get(@extension_map, ext) do
      nil -> {:error, :unknown_format}
      {module, opts} -> {:ok, module, opts}
      module -> {:ok, module, []}
    end
  end

  @doc """
  Parse file using detected format.
  """
  @spec parse(Path.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def parse(path, opts \\ []) do
    case detect(path) do
      {:ok, module, default_opts} ->
        module.parse(path, Keyword.merge(default_opts, opts))
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### 6. Add Dataset Delegates

Add to `lib/dataset_manager/dataset.ex`:

```elixir
@spec to_text(t(), Path.t(), keyword()) :: :ok | {:error, term()}
def to_text(%__MODULE__{} = dataset, path, opts \\ []) do
  HfDatasetsEx.Export.Text.write(dataset, path, opts)
end

@spec to_arrow(t(), Path.t(), keyword()) :: :ok | {:error, term()}
def to_arrow(%__MODULE__{} = dataset, path, opts \\ []) do
  HfDatasetsEx.Export.Arrow.write(dataset, path, opts)
end
```

## TDD Approach

### Step 1: Write Tests First

Create `test/dataset_manager/format/text_test.exs`:

```elixir
defmodule HfDatasetsEx.Format.TextTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Format.Text

  @fixtures_dir Path.join(System.tmp_dir!(), "text_format_test_#{:rand.uniform(100000)}")

  setup_all do
    File.mkdir_p!(@fixtures_dir)

    # Basic text file
    File.write!(Path.join(@fixtures_dir, "basic.txt"), """
    Hello world
    How are you
    Goodbye
    """)

    # File with empty lines
    File.write!(Path.join(@fixtures_dir, "empty_lines.txt"), """
    Line 1

    Line 2

    Line 3
    """)

    # Unicode file
    File.write!(Path.join(@fixtures_dir, "unicode.txt"), """
    Hello 世界
    Привет мир
    مرحبا بالعالم
    """)

    on_exit(fn -> File.rm_rf!(@fixtures_dir) end)

    :ok
  end

  describe "parse/2" do
    test "parses basic text file" do
      path = Path.join(@fixtures_dir, "basic.txt")

      assert {:ok, items} = Text.parse(path)
      assert length(items) == 3
      assert hd(items) == %{"text" => "Hello world"}
    end

    test "skips empty lines by default" do
      path = Path.join(@fixtures_dir, "empty_lines.txt")

      assert {:ok, items} = Text.parse(path)
      assert length(items) == 3
    end

    test "keeps empty lines when skip_empty: false" do
      path = Path.join(@fixtures_dir, "empty_lines.txt")

      assert {:ok, items} = Text.parse(path, skip_empty: false)
      assert length(items) == 5
    end

    test "uses custom column name" do
      path = Path.join(@fixtures_dir, "basic.txt")

      assert {:ok, items} = Text.parse(path, column: "content")
      assert hd(items) == %{"content" => "Hello world"}
    end

    test "handles unicode" do
      path = Path.join(@fixtures_dir, "unicode.txt")

      assert {:ok, items} = Text.parse(path)
      assert length(items) == 3
      assert hd(items)["text"] =~ "世界"
    end
  end

  describe "parse_stream/2" do
    test "returns stream" do
      path = Path.join(@fixtures_dir, "basic.txt")

      stream = Text.parse_stream(path)
      items = Enum.to_list(stream)

      assert length(items) == 3
    end

    test "stream is lazy" do
      path = Path.join(@fixtures_dir, "basic.txt")

      stream = Text.parse_stream(path)

      # Take only 1
      assert [first] = Enum.take(stream, 1)
      assert first["text"] == "Hello world"
    end
  end
end
```

Create `test/dataset_manager/format/arrow_test.exs`:

```elixir
defmodule HfDatasetsEx.Format.ArrowTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Format.Arrow
  alias HfDatasetsEx.Export

  @fixtures_dir Path.join(System.tmp_dir!(), "arrow_format_test_#{:rand.uniform(100000)}")

  setup_all do
    File.mkdir_p!(@fixtures_dir)

    # Create Arrow file
    df = Explorer.DataFrame.new(%{
      "name" => ["Alice", "Bob", "Charlie"],
      "age" => [30, 25, 35],
      "score" => [95.5, 87.2, 91.8]
    })

    path = Path.join(@fixtures_dir, "test.arrow")
    Explorer.DataFrame.to_ipc(df, path)

    on_exit(fn -> File.rm_rf!(@fixtures_dir) end)

    {:ok, path: path}
  end

  describe "parse/2" do
    test "parses Arrow file", %{path: path} do
      assert {:ok, items} = Arrow.parse(path)
      assert length(items) == 3
      assert hd(items)["name"] == "Alice"
    end

    test "selects specific columns", %{path: path} do
      assert {:ok, items} = Arrow.parse(path, columns: ["name", "age"])

      keys = Map.keys(hd(items))
      assert "name" in keys
      assert "age" in keys
      refute "score" in keys
    end

    test "returns error for missing file" do
      assert {:error, _} = Arrow.parse("/nonexistent.arrow")
    end
  end

  describe "round-trip" do
    test "write and read preserves data" do
      dataset = HfDatasetsEx.Dataset.from_list([
        %{"x" => 1, "y" => "a"},
        %{"x" => 2, "y" => "b"}
      ])

      path = Path.join(@fixtures_dir, "roundtrip.arrow")

      assert :ok = Export.Arrow.write(dataset, path)
      assert {:ok, items} = Arrow.parse(path)

      assert length(items) == 2
      assert hd(items)["x"] == 1
    end
  end
end
```

Create `test/dataset_manager/export/text_test.exs`:

```elixir
defmodule HfDatasetsEx.Export.TextTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.{Dataset, Export}

  @fixtures_dir Path.join(System.tmp_dir!(), "text_export_test_#{:rand.uniform(100000)}")

  setup do
    File.mkdir_p!(@fixtures_dir)
    on_exit(fn -> File.rm_rf!(@fixtures_dir) end)
    :ok
  end

  describe "write/3" do
    test "exports dataset to text file" do
      dataset = Dataset.from_list([
        %{"text" => "Hello"},
        %{"text" => "World"}
      ])

      path = Path.join(@fixtures_dir, "out.txt")
      assert :ok = Export.Text.write(dataset, path)

      content = File.read!(path)
      assert content == "Hello\nWorld\n"
    end

    test "uses custom column" do
      dataset = Dataset.from_list([
        %{"content" => "Line 1"},
        %{"content" => "Line 2"}
      ])

      path = Path.join(@fixtures_dir, "out.txt")
      assert :ok = Export.Text.write(dataset, path, column: "content")

      content = File.read!(path)
      assert content == "Line 1\nLine 2\n"
    end
  end
end
```

### Step 2: Run Tests

```bash
mix test test/dataset_manager/format/text_test.exs
mix test test/dataset_manager/format/arrow_test.exs
mix test test/dataset_manager/export/text_test.exs
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
- [ ] Text files read correctly with streaming
- [ ] Arrow files read/write correctly
- [ ] Round-trip tests pass

## Files to Create/Modify

| File | Action |
|------|--------|
| `lib/dataset_manager/format/text.ex` | Create |
| `lib/dataset_manager/format/arrow.ex` | Create |
| `lib/dataset_manager/export/text.ex` | Create |
| `lib/dataset_manager/export/arrow.ex` | Create |
| `lib/dataset_manager/format.ex` | Update registry |
| `lib/dataset_manager/dataset.ex` | Add delegates |
| `test/dataset_manager/format/text_test.exs` | Create |
| `test/dataset_manager/format/arrow_test.exs` | Create |
| `test/dataset_manager/export/text_test.exs` | Create |

## Dependencies

No new dependencies needed. Uses:
- `explorer` (already present) for Arrow IPC support
