# Implementation Prompt: Nx Tensor Formatter

## Priority: P0 (Critical)

## Objective

Implement an Nx tensor formatter that converts dataset columns to Nx tensors for ML training integration.

## Required Reading

Before starting, read these files completely:

```
lib/dataset_manager/dataset.ex
lib/dataset_manager/features.ex
lib/dataset_manager/features/value.ex
lib/dataset_manager/features/class_label.ex
lib/dataset_manager/features/sequence.ex
mix.exs (for dependencies)
docs/20251231/gap_analysis/05_formatters.md
```

## Context

The Python `datasets` library supports `.set_format("torch")`, `.set_format("numpy")`, etc. to automatically convert data to tensors during iteration. This is critical for ML training pipelines.

Elixir uses Nx as the unified tensor library (with backends like EXLA, Torchx).

Current state:
- No Nx dependency in mix.exs (needs to be added)
- No formatting system exists
- Dataset iteration returns plain maps

## Implementation Requirements

### 1. Add Nx Dependency

Update `mix.exs`:

```elixir
defp deps do
  [
    # ... existing deps ...
    {:nx, "~> 0.9"}
  ]
end
```

### 2. Create Formatter Behaviour

Create `lib/dataset_manager/formatter.ex`:

```elixir
defmodule HfDatasetsEx.Formatter do
  @moduledoc """
  Behaviour for dataset output formatters.
  """

  @type format_type :: :elixir | :nx | :explorer | :custom

  @callback format_row(map(), keyword()) :: any()
  @callback format_batch([map()], keyword()) :: any()

  @optional_callbacks [format_batch: 2]

  @spec get(format_type()) :: module()
  def get(:elixir), do: HfDatasetsEx.Formatter.Elixir
  def get(:nx), do: HfDatasetsEx.Formatter.Nx
  def get(:explorer), do: HfDatasetsEx.Formatter.Explorer
  def get(:custom), do: HfDatasetsEx.Formatter.Custom
  def get(other), do: raise ArgumentError, "Unknown format: #{inspect(other)}"
end
```

### 3. Create Elixir Formatter (Default)

Create `lib/dataset_manager/formatter/elixir.ex`:

```elixir
defmodule HfDatasetsEx.Formatter.Elixir do
  @behaviour HfDatasetsEx.Formatter

  @impl true
  def format_row(row, _opts), do: row

  @impl true
  def format_batch(rows, _opts), do: rows
end
```

### 4. Create Nx Formatter

Create `lib/dataset_manager/formatter/nx.ex`:

```elixir
defmodule HfDatasetsEx.Formatter.Nx do
  @moduledoc """
  Formatter that converts numeric data to Nx tensors.
  """

  @behaviour HfDatasetsEx.Formatter

  @type_map %{
    int8: {:s, 8},
    int16: {:s, 16},
    int32: {:s, 32},
    int64: {:s, 64},
    uint8: {:u, 8},
    uint16: {:u, 16},
    uint32: {:u, 32},
    uint64: {:u, 64},
    float16: {:f, 16},
    float32: {:f, 32},
    float64: {:f, 64},
    bool: {:u, 8}
  }

  @impl true
  @spec format_row(map(), keyword()) :: map()
  def format_row(row, opts \\ []) do
    columns = Keyword.get(opts, :columns)
    dtype = Keyword.get(opts, :dtype)

    row
    |> maybe_select_columns(columns)
    |> Enum.map(fn {key, value} ->
      {key, to_tensor(value, dtype)}
    end)
    |> Map.new()
  end

  @impl true
  @spec format_batch([map()], keyword()) :: map()
  def format_batch(rows, opts \\ []) when rows != [] do
    columns = Keyword.get(opts, :columns)
    dtype = Keyword.get(opts, :dtype)

    keys = rows |> hd() |> Map.keys()
    keys = if columns, do: Enum.filter(keys, &(&1 in columns)), else: keys

    Map.new(keys, fn key ->
      values = Enum.map(rows, &Map.get(&1, key))
      {key, stack_to_tensor(values, dtype)}
    end)
  end

  def format_batch([], _opts), do: %{}

  @doc """
  Convert Features dtype to Nx type.
  """
  @spec dtype_to_nx(atom()) :: Nx.Type.t()
  def dtype_to_nx(dtype) do
    Map.get(@type_map, dtype, {:f, 32})
  end

  defp maybe_select_columns(row, nil), do: row
  defp maybe_select_columns(row, columns) do
    Map.take(row, columns)
  end

  defp to_tensor(value, dtype) when is_number(value) do
    opts = if dtype, do: [type: dtype_to_nx(dtype)], else: []
    Nx.tensor(value, opts)
  end

  defp to_tensor(value, dtype) when is_list(value) do
    if all_numeric?(value) do
      opts = if dtype, do: [type: dtype_to_nx(dtype)], else: []
      Nx.tensor(value, opts)
    else
      value
    end
  end

  defp to_tensor(value, _dtype), do: value

  defp stack_to_tensor(values, dtype) do
    cond do
      Enum.all?(values, &is_number/1) ->
        opts = if dtype, do: [type: dtype_to_nx(dtype)], else: []
        Nx.tensor(values, opts)

      Enum.all?(values, &is_list/1) and Enum.all?(values, &all_numeric?/1) ->
        opts = if dtype, do: [type: dtype_to_nx(dtype)], else: []
        Nx.stack(Enum.map(values, &Nx.tensor(&1, opts)))

      true ->
        values
    end
  end

  defp all_numeric?([]), do: true
  defp all_numeric?([h | t]) when is_number(h), do: all_numeric?(t)
  defp all_numeric?([h | t]) when is_list(h), do: all_numeric?(h) and all_numeric?(t)
  defp all_numeric?(_), do: false
end
```

### 5. Update Dataset with Format Support

Add to `lib/dataset_manager/dataset.ex`:

```elixir
defmodule HfDatasetsEx.Dataset do
  # Add to defstruct
  defstruct [
    :name,
    :version,
    :items,
    :metadata,
    :features,
    format: :elixir,
    format_columns: nil,
    format_opts: []
  ]

  @doc """
  Set the output format for the dataset.

  ## Options

    * `:columns` - List of columns to include in formatted output
    * `:dtype` - Force specific data type (e.g., `:float32`)

  ## Examples

      dataset
      |> Dataset.set_format(:nx, columns: ["input_ids", "labels"])
      |> Enum.each(fn batch -> ... end)

  """
  @spec set_format(t(), Formatter.format_type(), keyword()) :: t()
  def set_format(%__MODULE__{} = dataset, format, opts \\ []) do
    %{dataset |
      format: format,
      format_columns: Keyword.get(opts, :columns),
      format_opts: opts
    }
  end

  @doc """
  Return a copy with the specified format (doesn't modify original).
  """
  @spec with_format(t(), Formatter.format_type(), keyword()) :: t()
  def with_format(%__MODULE__{} = dataset, format, opts \\ []) do
    set_format(dataset, format, opts)
  end

  @doc """
  Reset format to default (Elixir maps).
  """
  @spec reset_format(t()) :: t()
  def reset_format(%__MODULE__{} = dataset) do
    %{dataset | format: :elixir, format_columns: nil, format_opts: []}
  end

  @doc """
  Iterate over dataset in batches with formatting applied.

  ## Options

    * `:batch_size` - Number of items per batch (default: 32)
    * `:drop_last` - Drop last batch if incomplete (default: false)

  ## Examples

      dataset
      |> Dataset.set_format(:nx)
      |> Dataset.iter(batch_size: 32)
      |> Enum.each(fn batch ->
        # batch is %{"col1" => Nx.Tensor, "col2" => Nx.Tensor}
      end)

  """
  @spec iter(t(), keyword()) :: Enumerable.t()
  def iter(%__MODULE__{} = dataset, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 32)
    drop_last = Keyword.get(opts, :drop_last, false)

    formatter = Formatter.get(dataset.format)
    format_opts = dataset.format_opts

    chunker = if drop_last, do: :discard, else: []

    dataset.items
    |> Stream.chunk_every(batch_size, batch_size, chunker)
    |> Stream.map(&formatter.format_batch(&1, format_opts))
  end

  # Update Enumerable implementation to use formatter
  defimpl Enumerable do
    def count(%Dataset{items: items}), do: {:ok, length(items)}

    def member?(%Dataset{items: items}, element), do: {:ok, element in items}

    def slice(%Dataset{items: items}) do
      {:ok, length(items), &Enum.slice(items, &1, &2)}
    end

    def reduce(%Dataset{items: items, format: format, format_opts: opts}, acc, fun) do
      formatter = HfDatasetsEx.Formatter.get(format)

      items
      |> Stream.map(&formatter.format_row(&1, opts))
      |> Enumerable.reduce(acc, fun)
    end
  end
end
```

## TDD Approach

### Step 1: Write Tests First

Create `test/dataset_manager/formatter_test.exs`:

```elixir
defmodule HfDatasetsEx.FormatterTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.{Dataset, Formatter}

  describe "Formatter.Nx" do
    test "format_row converts numbers to tensors" do
      row = %{"x" => 1.0, "y" => 2.0}
      formatted = Formatter.Nx.format_row(row)

      assert Nx.is_tensor(formatted["x"])
      assert Nx.to_number(formatted["x"]) == 1.0
    end

    test "format_row preserves strings" do
      row = %{"text" => "hello", "x" => 1.0}
      formatted = Formatter.Nx.format_row(row)

      assert formatted["text"] == "hello"
      assert Nx.is_tensor(formatted["x"])
    end

    test "format_row converts lists of numbers" do
      row = %{"embedding" => [1.0, 2.0, 3.0]}
      formatted = Formatter.Nx.format_row(row)

      assert Nx.is_tensor(formatted["embedding"])
      assert Nx.shape(formatted["embedding"]) == {3}
    end

    test "format_row respects :columns option" do
      row = %{"x" => 1.0, "y" => 2.0, "z" => 3.0}
      formatted = Formatter.Nx.format_row(row, columns: ["x", "y"])

      assert Map.keys(formatted) == ["x", "y"]
    end

    test "format_row respects :dtype option" do
      row = %{"x" => 1}
      formatted = Formatter.Nx.format_row(row, dtype: :float32)

      assert Nx.type(formatted["x"]) == {:f, 32}
    end

    test "format_batch stacks scalars into 1D tensor" do
      rows = [
        %{"x" => 1.0},
        %{"x" => 2.0},
        %{"x" => 3.0}
      ]

      formatted = Formatter.Nx.format_batch(rows)

      assert Nx.is_tensor(formatted["x"])
      assert Nx.shape(formatted["x"]) == {3}
    end

    test "format_batch stacks lists into 2D tensor" do
      rows = [
        %{"embedding" => [1.0, 2.0]},
        %{"embedding" => [3.0, 4.0]}
      ]

      formatted = Formatter.Nx.format_batch(rows)

      assert Nx.is_tensor(formatted["embedding"])
      assert Nx.shape(formatted["embedding"]) == {2, 2}
    end

    test "format_batch handles mixed types" do
      rows = [
        %{"text" => "hello", "x" => 1.0},
        %{"text" => "world", "x" => 2.0}
      ]

      formatted = Formatter.Nx.format_batch(rows)

      assert formatted["text"] == ["hello", "world"]
      assert Nx.is_tensor(formatted["x"])
    end

    test "format_batch handles empty list" do
      assert Formatter.Nx.format_batch([]) == %{}
    end
  end

  describe "Dataset with Nx format" do
    test "set_format changes iteration output" do
      dataset = Dataset.from_list([
        %{"x" => 1.0, "y" => 2.0},
        %{"x" => 3.0, "y" => 4.0}
      ])

      formatted = Dataset.set_format(dataset, :nx)

      [first | _] = Enum.to_list(formatted)

      assert Nx.is_tensor(first["x"])
    end

    test "iter returns batched tensors" do
      dataset =
        1..10
        |> Enum.map(&%{"x" => &1 * 1.0})
        |> Dataset.from_list()
        |> Dataset.set_format(:nx)

      batches = dataset |> Dataset.iter(batch_size: 3) |> Enum.to_list()

      assert length(batches) == 4  # 3+3+3+1

      [first | _] = batches
      assert Nx.shape(first["x"]) == {3}
    end

    test "iter with drop_last discards incomplete batches" do
      dataset =
        1..10
        |> Enum.map(&%{"x" => &1 * 1.0})
        |> Dataset.from_list()
        |> Dataset.set_format(:nx)

      batches = dataset |> Dataset.iter(batch_size: 3, drop_last: true) |> Enum.to_list()

      assert length(batches) == 3  # Drops last batch of 1
    end

    test "with_format returns new dataset without modifying original" do
      original = Dataset.from_list([%{"x" => 1.0}])

      formatted = Dataset.with_format(original, :nx)

      assert original.format == :elixir
      assert formatted.format == :nx
    end

    test "reset_format returns to default" do
      dataset =
        Dataset.from_list([%{"x" => 1.0}])
        |> Dataset.set_format(:nx)
        |> Dataset.reset_format()

      assert dataset.format == :elixir
    end
  end

  describe "dtype_to_nx/1" do
    test "maps feature types to Nx types" do
      assert Formatter.Nx.dtype_to_nx(:int32) == {:s, 32}
      assert Formatter.Nx.dtype_to_nx(:float32) == {:f, 32}
      assert Formatter.Nx.dtype_to_nx(:uint8) == {:u, 8}
    end
  end
end
```

### Step 2: Run Tests (They Should Fail)

```bash
mix deps.get  # Get Nx
mix test test/dataset_manager/formatter_test.exs
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
- [ ] Nx tensors have correct shapes
- [ ] Batch iteration works for training loops
- [ ] String/non-numeric columns preserved as-is

## Files to Create/Modify

| File | Action |
|------|--------|
| `mix.exs` | Add `nx` dependency |
| `lib/dataset_manager/formatter.ex` | Create behaviour |
| `lib/dataset_manager/formatter/elixir.ex` | Create |
| `lib/dataset_manager/formatter/nx.ex` | Create |
| `lib/dataset_manager/dataset.ex` | Add format fields and functions |
| `test/dataset_manager/formatter_test.exs` | Create |

## Edge Cases to Handle

1. Empty dataset
2. Nested lists (multi-dimensional arrays)
3. Mixed types in same column across rows
4. Very large tensors (memory consideration)
5. Backend selection (EXLA, Torchx)
6. NaN and infinity handling
