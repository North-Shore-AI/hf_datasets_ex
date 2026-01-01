# Gap Analysis: Output Formatters

## Overview

The Python `datasets` library supports 9 output formatters that control how data is returned from indexing and iteration. The Elixir port only uses native Elixir data structures (maps/lists).

## Python Formatters

| Formatter | Aliases | Output Type |
|-----------|---------|-------------|
| `PythonFormatter` | `python` (default) | dict, list |
| `ArrowFormatter` | `arrow`, `pa`, `pyarrow` | PyArrow Table/Array |
| `NumpyFormatter` | `numpy`, `np` | NumPy arrays |
| `PandasFormatter` | `pandas`, `pd` | Pandas DataFrame/Series |
| `PolarsFormatter` | `polars`, `pl` | Polars DataFrame/Series |
| `TorchFormatter` | `torch`, `pt`, `pytorch` | PyTorch tensors |
| `TensorflowFormatter` | `tensorflow`, `tf` | TensorFlow tensors |
| `JaxFormatter` | `jax` | JAX arrays |
| `CustomFormatter` | `custom` | User-defined |

## Elixir Equivalent Formatters

### P0 - Critical (Required for ML Training)

#### NxFormatter (equivalent to NumPy/Torch/TF/JAX)

In Elixir, Nx is the unified tensor library that supports multiple backends (EXLA, Torchx, etc.).

```elixir
defmodule HfDatasetsEx.Formatter.Nx do
  @behaviour HfDatasetsEx.Formatter

  @type options :: [
    columns: [String.t()] | nil,
    dtype: Nx.Type.t() | nil,
    backend: module() | nil
  ]

  @impl true
  @spec format_row(map(), options()) :: map()
  def format_row(row, opts \\ []) do
    columns = Keyword.get(opts, :columns) || Map.keys(row)
    dtype = Keyword.get(opts, :dtype)

    Map.new(columns, fn col ->
      value = Map.get(row, col)
      {col, to_tensor(value, dtype)}
    end)
  end

  @impl true
  @spec format_batch([map()], options()) :: map()
  def format_batch(rows, opts \\ []) do
    columns = Keyword.get(opts, :columns) || Map.keys(hd(rows))
    dtype = Keyword.get(opts, :dtype)

    Map.new(columns, fn col ->
      values = Enum.map(rows, &Map.get(&1, col))
      {col, stack_to_tensor(values, dtype)}
    end)
  end

  defp to_tensor(value, dtype) when is_number(value) do
    opts = if dtype, do: [type: dtype], else: []
    Nx.tensor(value, opts)
  end

  defp to_tensor(value, dtype) when is_list(value) do
    opts = if dtype, do: [type: dtype], else: []
    Nx.tensor(value, opts)
  end

  defp to_tensor(value, _dtype) when is_binary(value) do
    # Keep strings as-is
    value
  end

  defp to_tensor(value, _dtype) do
    value
  end

  defp stack_to_tensor(values, dtype) when is_list(values) do
    if Enum.all?(values, &is_number/1) or Enum.all?(values, &is_list/1) do
      opts = if dtype, do: [type: dtype], else: []
      Nx.stack(Enum.map(values, &Nx.tensor(&1, opts)))
    else
      values
    end
  end
end
```

### P1 - High Priority

#### ExplorerFormatter (equivalent to Pandas/Polars)

```elixir
defmodule HfDatasetsEx.Formatter.Explorer do
  @behaviour HfDatasetsEx.Formatter

  @impl true
  @spec format_batch([map()], keyword()) :: Explorer.DataFrame.t()
  def format_batch(rows, opts \\ []) do
    columns = Keyword.get(opts, :columns)

    df = Explorer.DataFrame.new(rows)

    if columns do
      Explorer.DataFrame.select(df, columns)
    else
      df
    end
  end

  @impl true
  @spec format_row(map(), keyword()) :: Explorer.Series.t() | map()
  def format_row(row, _opts \\ []) do
    # Single row as Series doesn't make much sense
    # Return as-is or wrap in DataFrame
    row
  end
end
```

#### ArrowFormatter

```elixir
defmodule HfDatasetsEx.Formatter.Arrow do
  @behaviour HfDatasetsEx.Formatter

  @impl true
  @spec format_batch([map()], keyword()) :: binary()
  def format_batch(rows, _opts \\ []) do
    # Convert to Arrow IPC format
    df = Explorer.DataFrame.new(rows)

    # Explorer can dump to Arrow format
    {:ok, arrow_binary} = Explorer.DataFrame.dump_ipc(df)
    arrow_binary
  end
end
```

### P2 - Custom Formatter

```elixir
defmodule HfDatasetsEx.Formatter.Custom do
  @behaviour HfDatasetsEx.Formatter

  @type transform_fn :: (map() -> any())

  @impl true
  @spec format_row(map(), keyword()) :: any()
  def format_row(row, opts) do
    transform = Keyword.fetch!(opts, :transform)
    transform.(row)
  end

  @impl true
  @spec format_batch([map()], keyword()) :: any()
  def format_batch(rows, opts) do
    transform = Keyword.fetch!(opts, :transform)

    case Keyword.get(opts, :batched, false) do
      true -> transform.(rows)
      false -> Enum.map(rows, transform)
    end
  end
end
```

## Formatter Behaviour

```elixir
defmodule HfDatasetsEx.Formatter do
  @callback format_row(map(), keyword()) :: any()
  @callback format_batch([map()], keyword()) :: any()

  @optional_callbacks [format_batch: 2]

  @type formatter_type :: :elixir | :nx | :explorer | :arrow | :custom

  @formatters %{
    elixir: HfDatasetsEx.Formatter.Elixir,
    nx: HfDatasetsEx.Formatter.Nx,
    explorer: HfDatasetsEx.Formatter.Explorer,
    arrow: HfDatasetsEx.Formatter.Arrow,
    custom: HfDatasetsEx.Formatter.Custom
  }

  @spec get(formatter_type()) :: module()
  def get(type) do
    Map.fetch!(@formatters, type)
  end
end
```

## Integration with Dataset

```elixir
defmodule HfDatasetsEx.Dataset do
  # Add format field to struct
  defstruct [
    :name,
    :version,
    :items,
    :metadata,
    :features,
    format: :elixir,        # Add
    format_columns: nil,    # Add
    format_opts: []         # Add
  ]

  @spec set_format(t(), atom(), keyword()) :: t()
  def set_format(%__MODULE__{} = dataset, format, opts \\ []) do
    columns = Keyword.get(opts, :columns)

    %{dataset |
      format: format,
      format_columns: columns,
      format_opts: opts
    }
  end

  @spec with_format(t(), atom(), keyword()) :: t()
  def with_format(%__MODULE__{} = dataset, format, opts \\ []) do
    # Returns new dataset with format, doesn't modify original
    set_format(dataset, format, opts)
  end

  @spec reset_format(t()) :: t()
  def reset_format(%__MODULE__{} = dataset) do
    %{dataset | format: :elixir, format_columns: nil, format_opts: []}
  end

  # Update Access implementation
  def fetch(%__MODULE__{} = dataset, key) when is_integer(key) do
    item = Enum.at(dataset.items, key)
    formatted = apply_format(item, dataset)
    {:ok, formatted}
  end

  defp apply_format(item, %{format: :elixir}), do: item
  defp apply_format(item, %{format: format, format_opts: opts}) do
    formatter = Formatter.get(format)
    formatter.format_row(item, opts)
  end

  # Update iteration
  defimpl Enumerable do
    def reduce(%Dataset{} = dataset, acc, fun) do
      formatter = Formatter.get(dataset.format)

      dataset.items
      |> Enum.map(&formatter.format_row(&1, dataset.format_opts))
      |> Enumerable.reduce(acc, fun)
    end
  end
end
```

## Batch Formatting for Training

```elixir
defmodule HfDatasetsEx.Dataset do
  @doc """
  Iterate in batches with formatting applied.

  ## Examples

      dataset
      |> Dataset.set_format(:nx, columns: ["input_ids", "labels"])
      |> Dataset.iter(batch_size: 32)
      |> Enum.each(fn batch ->
        # batch is %{"input_ids" => Nx.Tensor, "labels" => Nx.Tensor}
        Axon.Training.step(model, batch)
      end)
  """
  @spec iter(t(), keyword()) :: Enumerable.t()
  def iter(%__MODULE__{} = dataset, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 32)
    drop_last = Keyword.get(opts, :drop_last, false)

    formatter = Formatter.get(dataset.format)

    dataset.items
    |> Stream.chunk_every(batch_size, batch_size, if(drop_last, do: :discard, else: []))
    |> Stream.map(&formatter.format_batch(&1, dataset.format_opts))
  end
end
```

## Type Conversion for Nx

```elixir
defmodule HfDatasetsEx.Formatter.Nx do
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
    bool: {:u, 8},
    bfloat16: {:bf, 16}
  }

  @spec features_dtype_to_nx(atom()) :: Nx.Type.t()
  def features_dtype_to_nx(dtype) do
    Map.get(@type_map, dtype, {:f, 32})
  end

  @doc """
  Infer Nx types from Features schema.
  """
  @spec infer_types(HfDatasetsEx.Features.t()) :: %{String.t() => Nx.Type.t()}
  def infer_types(%Features{schema: schema}) do
    Map.new(schema, fn {name, feature} ->
      nx_type = case feature do
        %Features.Value{dtype: dtype} -> features_dtype_to_nx(dtype)
        %Features.ClassLabel{} -> {:s, 64}
        %Features.Sequence{feature: %Features.Value{dtype: dtype}} ->
          features_dtype_to_nx(dtype)
        _ -> nil
      end

      {name, nx_type}
    end)
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end
end
```

## Files to Create

| File | Purpose |
|------|---------|
| `lib/dataset_manager/formatter.ex` | Formatter behaviour and registry |
| `lib/dataset_manager/formatter/elixir.ex` | Default Elixir formatter |
| `lib/dataset_manager/formatter/nx.ex` | Nx tensor formatter |
| `lib/dataset_manager/formatter/explorer.ex` | Explorer DataFrame formatter |
| `lib/dataset_manager/formatter/arrow.ex` | Arrow binary formatter |
| `lib/dataset_manager/formatter/custom.ex` | Custom transform formatter |
| `test/dataset_manager/formatter_test.exs` | Formatter tests |
| `test/dataset_manager/formatter/nx_test.exs` | Nx-specific tests |

## Dependencies

| Formatter | Dependency | Status |
|-----------|------------|--------|
| Nx | `nx` | Add to deps |
| Explorer | `explorer` | ✅ Already have |
| Arrow | `explorer` | ✅ Already have |

## Testing Requirements

```elixir
# test/dataset_manager/formatter/nx_test.exs
defmodule HfDatasetsEx.Formatter.NxTest do
  use ExUnit.Case

  alias HfDatasetsEx.{Dataset, Formatter}

  test "format_row converts numbers to tensors" do
    row = %{"x" => 1.0, "y" => 2.0}
    formatted = Formatter.Nx.format_row(row)

    assert Nx.tensor?(formatted["x"])
    assert Nx.to_number(formatted["x"]) == 1.0
  end

  test "format_batch stacks tensors" do
    rows = [
      %{"x" => [1, 2, 3]},
      %{"x" => [4, 5, 6]}
    ]

    formatted = Formatter.Nx.format_batch(rows)

    assert Nx.tensor?(formatted["x"])
    assert Nx.shape(formatted["x"]) == {2, 3}
  end

  test "dataset iteration with nx format" do
    dataset =
      Dataset.from_list([
        %{"x" => 1.0, "label" => 0},
        %{"x" => 2.0, "label" => 1}
      ])
      |> Dataset.set_format(:nx)

    [first | _] = Enum.to_list(dataset)

    assert Nx.tensor?(first["x"])
    assert Nx.tensor?(first["label"])
  end
end
```

## Performance Considerations

1. **Lazy Conversion**: Only convert to tensors when accessed, not upfront
2. **Batch Stacking**: Use `Nx.stack` for efficient batch creation
3. **Backend Selection**: Allow specifying Nx backend (EXLA for GPU)
4. **Memory**: Large datasets should use streaming to avoid OOM

```elixir
# Efficient training loop
dataset
|> Dataset.set_format(:nx, backend: EXLA.Backend)
|> Dataset.shuffle(seed: 42)
|> Dataset.iter(batch_size: 32, drop_last: true)
|> Stream.each(fn batch ->
  # batch tensors are on GPU if using EXLA
  Axon.Training.step(model, batch)
end)
|> Stream.run()
```
