# Implementation Prompt: DatasetDict Operations

## Task

Add `map/3` and `filter/3` functions to `HfDatasetsEx.DatasetDict` that apply transformations across all splits.

## Pre-Implementation Reading

Read these files to understand the existing codebase:

1. `lib/dataset_manager/dataset_dict.ex` - Current DatasetDict implementation
2. `lib/dataset_manager/dataset.ex` - Dataset.map/filter patterns to follow
3. `test/dataset_manager/dataset_dict_test.exs` - Existing test patterns

## Context

The `DatasetDict` struct holds multiple `Dataset` structs keyed by split name (e.g., "train", "test"). Currently, users must manually iterate over splits to apply the same transformation. We need to add convenience methods.

## Requirements

### 1. DatasetDict.map/3

```elixir
@doc """
Apply a map function to all splits in the DatasetDict.

## Options

  * `:cache` - Enable caching (default: true)
  * All other options passed to Dataset.map/3

## Examples

    dd = DatasetDict.map(dd, fn item ->
      Map.put(item, "processed", true)
    end)

"""
@spec map(t(), (map() -> map()), keyword()) :: t()
```

### 2. DatasetDict.filter/3

```elixir
@doc """
Filter all splits in the DatasetDict with a predicate.

## Options

  * `:cache` - Enable caching (default: true)
  * All other options passed to Dataset.filter/3

## Examples

    dd = DatasetDict.filter(dd, fn item ->
      item["score"] > 0.5
    end)

"""
@spec filter(t(), (map() -> boolean()), keyword()) :: t()
```

## File to Modify

`lib/dataset_manager/dataset_dict.ex`

## Current DatasetDict Structure

```elixir
defmodule HfDatasetsEx.DatasetDict do
  @type t :: %__MODULE__{
    datasets: %{String.t() => Dataset.t()}
  }

  defstruct [:datasets]
end
```

## Implementation Pattern

```elixir
def map(%__MODULE__{datasets: datasets} = dd, fun, opts \\ []) do
  new_datasets =
    datasets
    |> Map.new(fn {split_name, dataset} ->
      {split_name, Dataset.map(dataset, fun, opts)}
    end)

  %{dd | datasets: new_datasets}
end
```

## Tests to Add

Create or update `test/dataset_manager/dataset_dict_test.exs`:

```elixir
describe "map/3" do
  test "applies function to all splits" do
    dd = sample_dataset_dict()

    result = DatasetDict.map(dd, fn item ->
      Map.put(item, "new_field", 1)
    end)

    for {_split, dataset} <- result.datasets do
      assert Enum.all?(dataset.items, &Map.has_key?(&1, "new_field"))
    end
  end

  test "preserves split names" do
    dd = sample_dataset_dict()
    result = DatasetDict.map(dd, & &1)

    assert Map.keys(result.datasets) == Map.keys(dd.datasets)
  end
end

describe "filter/3" do
  test "filters all splits" do
    dd = sample_dataset_dict()

    result = DatasetDict.filter(dd, fn item ->
      item["value"] > 0
    end)

    for {_split, dataset} <- result.datasets do
      assert Enum.all?(dataset.items, &(&1["value"] > 0))
    end
  end

  test "can result in empty splits" do
    dd = sample_dataset_dict()

    result = DatasetDict.filter(dd, fn _ -> false end)

    for {_split, dataset} <- result.datasets do
      assert dataset.items == []
    end
  end
end

defp sample_dataset_dict do
  train = Dataset.from_list([
    %{"id" => 1, "value" => 10},
    %{"id" => 2, "value" => -5}
  ])
  test = Dataset.from_list([
    %{"id" => 3, "value" => 15},
    %{"id" => 4, "value" => -2}
  ])

  DatasetDict.new(%{"train" => train, "test" => test})
end
```

## Acceptance Criteria

1. `mix test test/dataset_manager/dataset_dict_test.exs` passes
2. `mix credo --strict` has no new issues
3. `mix dialyzer` has no new warnings
4. Functions have proper @doc and @spec annotations
