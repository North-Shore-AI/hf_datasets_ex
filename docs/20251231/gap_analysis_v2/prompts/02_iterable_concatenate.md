# Implementation Prompt: IterableDataset.concatenate/1

## Task

Add a `concatenate/1` function to `HfDatasetsEx.IterableDataset` that sequentially combines multiple IterableDatasets.

## Pre-Implementation Reading

Read these files to understand the existing codebase:

1. `lib/dataset_manager/iterable_dataset.ex` - Current IterableDataset implementation
2. `test/dataset_manager/iterable_dataset_test.exs` - Existing test patterns

## Context

When working with streaming datasets, users often need to combine multiple sources sequentially (e.g., multiple data files, or augmented copies of the same data). This should remain lazy.

## Requirements

### IterableDataset.concatenate/1

```elixir
@doc """
Concatenate multiple IterableDatasets sequentially.

Items are yielded from each dataset in order. The second dataset
only starts yielding after the first is exhausted, and so on.

## Examples

    combined = IterableDataset.concatenate([ds1, ds2, ds3])

    # Yields all items from ds1, then ds2, then ds3
    for item <- combined do
      process(item)
    end

"""
@spec concatenate([t()]) :: t()
```

## File to Modify

`lib/dataset_manager/iterable_dataset.ex`

## Implementation

```elixir
@doc """
Concatenate multiple IterableDatasets sequentially.
"""
@spec concatenate([t()]) :: t()
def concatenate([]), do: from_stream(Stream.map([], & &1), name: "empty")

def concatenate([single]), do: single

def concatenate([first | rest]) do
  streams = [first | rest] |> Enum.map(& &1.stream)
  combined = Stream.concat(streams)

  %__MODULE__{
    stream: combined,
    name: first.name <> "_concatenated",
    info: merge_info([first | rest])
  }
end

defp merge_info(datasets) do
  # Combine info from all datasets
  datasets
  |> Enum.map(& &1.info)
  |> Enum.reduce(%{}, &Map.merge(&2, &1))
end
```

## Alternative: Module Function

```elixir
# In HfDatasetsEx module or as standalone function
@spec concatenate_datasets([IterableDataset.t()]) :: IterableDataset.t()
def concatenate_datasets(datasets) do
  IterableDataset.concatenate(datasets)
end
```

## Tests to Add

Add to `test/dataset_manager/iterable_dataset_test.exs`:

```elixir
describe "concatenate/1" do
  test "concatenates multiple streams" do
    ds1 = IterableDataset.from_stream(
      Stream.map([1, 2], &%{x: &1}),
      name: "ds1"
    )
    ds2 = IterableDataset.from_stream(
      Stream.map([3, 4], &%{x: &1}),
      name: "ds2"
    )

    combined = IterableDataset.concatenate([ds1, ds2])
    items = IterableDataset.to_list(combined)

    assert Enum.map(items, & &1.x) == [1, 2, 3, 4]
  end

  test "handles empty list" do
    combined = IterableDataset.concatenate([])
    assert IterableDataset.to_list(combined) == []
  end

  test "handles single dataset" do
    ds = IterableDataset.from_stream(
      Stream.map([1, 2], &%{x: &1}),
      name: "single"
    )

    combined = IterableDataset.concatenate([ds])
    assert IterableDataset.to_list(combined) == IterableDataset.to_list(ds)
  end

  test "remains lazy" do
    counter = :counters.new(1, [:atomics])

    ds1 = IterableDataset.from_stream(
      Stream.map([1, 2], fn x ->
        :counters.add(counter, 1, 1)
        %{x: x}
      end),
      name: "ds1"
    )
    ds2 = IterableDataset.from_stream(
      Stream.map([3, 4], fn x ->
        :counters.add(counter, 1, 1)
        %{x: x}
      end),
      name: "ds2"
    )

    combined = IterableDataset.concatenate([ds1, ds2])

    # Before consumption, counter should be 0
    assert :counters.get(counter, 1) == 0

    # Take only 2 items
    IterableDataset.take(combined, 2)

    # Should have only processed 2 items
    assert :counters.get(counter, 1) == 2
  end

  test "preserves info from first dataset" do
    ds1 = IterableDataset.from_stream(
      Stream.map([1], &%{x: &1}),
      name: "ds1",
      info: %{source: "file1"}
    )
    ds2 = IterableDataset.from_stream(
      Stream.map([2], &%{x: &1}),
      name: "ds2",
      info: %{source: "file2"}
    )

    combined = IterableDataset.concatenate([ds1, ds2])

    # Info should be merged
    assert Map.has_key?(combined.info, :source)
  end
end
```

## Acceptance Criteria

1. `mix test test/dataset_manager/iterable_dataset_test.exs` passes
2. Concatenation remains lazy (no items processed until consumed)
3. `mix credo --strict` has no new issues
4. `mix dialyzer` has no new warnings
5. Function has proper @doc and @spec annotations
