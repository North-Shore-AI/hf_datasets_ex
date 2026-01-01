# Implementation Prompt: Dataset.with_transform and set_transform

## Task

Implement lazy on-access transforms for `Dataset`, allowing functions to be applied when items are accessed rather than immediately.

## Pre-Implementation Reading

Read these files to understand the existing codebase:

1. `lib/dataset_manager/dataset.ex` - Current Dataset implementation, see Access and Enumerable
2. `lib/dataset_manager/formatter/` - How formatting works on access
3. `test/dataset_manager/dataset_ops_test.exs` - Existing operation tests

## Context

In the Python `datasets` library, `set_transform` and `with_transform` allow users to define transformations that are applied lazily when data is accessed. This is useful for:
- Data augmentation (different random augmentation each epoch)
- Memory efficiency (transform on-demand)
- On-the-fly preprocessing

## Requirements

### 1. Dataset struct modification

Add transform fields to the Dataset struct:

```elixir
defstruct [
  # Existing fields...
  :transform,           # (map() -> map()) | nil
  :transform_columns    # [String.t()] | nil - columns to pass to transform
]
```

### 2. Dataset.set_transform/3

```elixir
@doc """
Set an on-access transform function.

The transform is applied lazily when items are accessed via enumeration or indexing.
Replaces any existing transform.

## Options

  * `:columns` - Only pass specified columns to transform function
  * `:output_all_columns` - Keep un-transformed columns in output (default: false)

## Examples

    # Apply augmentation on every access
    dataset = Dataset.set_transform(dataset, fn item ->
      Map.put(item, "augmented", random_augment(item["image"]))
    end)

    # With column filtering
    dataset = Dataset.set_transform(dataset, &tokenize/1, columns: ["text"])

"""
@spec set_transform(t(), (map() -> map()), keyword()) :: t()
```

### 3. Dataset.with_transform/3

```elixir
@doc """
Return a copy of the dataset with the given transform.

Unlike `set_transform/3`, this does not modify the original dataset.

## Examples

    augmented = Dataset.with_transform(dataset, &augment/1)
    # dataset is unchanged, augmented has the transform

"""
@spec with_transform(t(), (map() -> map()), keyword()) :: t()
```

### 4. Dataset.reset_transform/1

```elixir
@doc """
Remove any set transform.

## Examples

    dataset = Dataset.reset_transform(dataset)
    # dataset.transform is now nil

"""
@spec reset_transform(t()) :: t()
```

## File to Modify

`lib/dataset_manager/dataset.ex`

## Implementation

### Struct Update

```elixir
defmodule HfDatasetsEx.Dataset do
  defstruct [
    :name,
    :version,
    :items,
    :metadata,
    :features,
    :fingerprint,
    :format,
    :format_columns,
    :format_opts,
    :transform,          # NEW
    :transform_columns   # NEW
  ]
```

### Main Functions

```elixir
def set_transform(%__MODULE__{} = dataset, transform, opts \\ []) when is_function(transform, 1) do
  columns = Keyword.get(opts, :columns)

  %{dataset |
    transform: transform,
    transform_columns: columns
  }
end

def with_transform(%__MODULE__{} = dataset, transform, opts \\ []) do
  set_transform(dataset, transform, opts)
end

def reset_transform(%__MODULE__{} = dataset) do
  %{dataset |
    transform: nil,
    transform_columns: nil
  }
end
```

### Apply Transform Helper

```elixir
defp apply_transform(item, %__MODULE__{transform: nil}), do: item

defp apply_transform(item, %__MODULE__{transform: transform, transform_columns: nil}) do
  transform.(item)
end

defp apply_transform(item, %__MODULE__{transform: transform, transform_columns: columns}) do
  # Only pass specified columns to transform
  filtered = Map.take(item, columns)
  transformed = transform.(filtered)
  Map.merge(item, transformed)
end
```

### Update Enumerable Implementation

```elixir
defimpl Enumerable, for: HfDatasetsEx.Dataset do
  def reduce(%Dataset{items: items} = dataset, acc, fun) do
    items
    |> Stream.map(&Dataset.apply_item_transform(&1, dataset))
    |> Stream.map(&Dataset.apply_format(&1, dataset))
    |> Enumerable.reduce(acc, fun)
  end

  # ... other callbacks
end
```

### Update Access Implementation

```elixir
defimpl Access, for: HfDatasetsEx.Dataset do
  def fetch(%Dataset{items: items} = dataset, index) when is_integer(index) do
    case Enum.at(items, index) do
      nil -> :error
      item ->
        item = Dataset.apply_item_transform(item, dataset)
        item = Dataset.apply_format(item, dataset)
        {:ok, item}
    end
  end

  # ... other callbacks
end
```

## Tests

Create `test/dataset_manager/dataset_transform_test.exs`:

```elixir
defmodule HfDatasetsEx.Dataset.TransformTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Dataset

  describe "set_transform/3" do
    test "applies transform on enumeration" do
      dataset = Dataset.from_list([
        %{"value" => 1},
        %{"value" => 2}
      ])

      transformed = Dataset.set_transform(dataset, fn item ->
        Map.put(item, "doubled", item["value"] * 2)
      end)

      results = Enum.to_list(transformed)

      assert [%{"value" => 1, "doubled" => 2}, %{"value" => 2, "doubled" => 4}] = results
    end

    test "applies transform on indexing" do
      dataset = Dataset.from_list([%{"x" => 10}])

      transformed = Dataset.set_transform(dataset, fn item ->
        Map.put(item, "y", item["x"] + 1)
      end)

      assert %{"x" => 10, "y" => 11} = transformed[0]
    end

    test "respects columns option" do
      dataset = Dataset.from_list([
        %{"text" => "hello", "id" => 1}
      ])

      transformed = Dataset.set_transform(dataset, fn item ->
        # Only receives "text" column
        %{"upper" => String.upcase(item["text"])}
      end, columns: ["text"])

      result = Enum.at(transformed, 0)

      assert result["id"] == 1
      assert result["text"] == "hello"
      assert result["upper"] == "HELLO"
    end

    test "replaces existing transform" do
      dataset = Dataset.from_list([%{"x" => 1}])

      t1 = Dataset.set_transform(dataset, fn item -> Map.put(item, "a", 1) end)
      t2 = Dataset.set_transform(t1, fn item -> Map.put(item, "b", 2) end)

      result = Enum.at(t2, 0)

      refute Map.has_key?(result, "a")
      assert result["b"] == 2
    end
  end

  describe "with_transform/3" do
    test "returns new dataset without modifying original" do
      original = Dataset.from_list([%{"x" => 1}])

      transformed = Dataset.with_transform(original, fn item ->
        Map.put(item, "y", 2)
      end)

      # Original unchanged
      original_result = Enum.at(original, 0)
      refute Map.has_key?(original_result, "y")

      # Transformed has the change
      transformed_result = Enum.at(transformed, 0)
      assert transformed_result["y"] == 2
    end
  end

  describe "reset_transform/1" do
    test "removes transform" do
      dataset = Dataset.from_list([%{"x" => 1}])

      transformed = Dataset.set_transform(dataset, fn item ->
        Map.put(item, "y", 2)
      end)

      reset = Dataset.reset_transform(transformed)

      result = Enum.at(reset, 0)
      refute Map.has_key?(result, "y")
    end
  end

  describe "transform with format" do
    test "transform is applied before format" do
      dataset = Dataset.from_list([%{"values" => [1, 2, 3]}])

      dataset = Dataset.set_transform(dataset, fn item ->
        Map.put(item, "sum", Enum.sum(item["values"]))
      end)

      dataset = Dataset.set_format(dataset, :nx, columns: ["sum"])

      result = Enum.at(dataset, 0)

      assert is_struct(result["sum"], Nx.Tensor)
    end
  end

  describe "transform with iteration" do
    test "applies fresh transform on each iteration" do
      dataset = Dataset.from_list([%{"x" => 1}])

      # Track how many times transform is called
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      transformed = Dataset.set_transform(dataset, fn item ->
        Agent.update(counter, &(&1 + 1))
        item
      end)

      # First iteration
      Enum.to_list(transformed)
      assert Agent.get(counter, & &1) == 1

      # Second iteration - transform called again
      Enum.to_list(transformed)
      assert Agent.get(counter, & &1) == 2

      Agent.stop(counter)
    end
  end
end
```

## Edge Cases

1. **Transform returns different keys**: Should work - merged with original
2. **Transform raises error**: Should propagate with helpful message
3. **Nil columns option**: Apply to entire item
4. **Empty columns list**: Apply to empty map, merge result
5. **Transform with batching**: Apply per-item, not per-batch

## Acceptance Criteria

1. `mix test test/dataset_manager/dataset_transform_test.exs` passes
2. `mix credo --strict` has no new issues
3. `mix dialyzer` has no new warnings
4. Transforms work with all iteration methods (`Enum`, `iter/2`, indexing)
5. Transforms compose correctly with format settings
6. Documentation includes examples

## Python Parity Notes

The Python implementation has additional features we may want to add later:
- `with_indices` parameter to pass item index to transform
- `with_rank` parameter for distributed training
- Batch-level transforms

These can be added as future enhancements.
