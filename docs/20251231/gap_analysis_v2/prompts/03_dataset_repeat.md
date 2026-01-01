# Implementation Prompt: Dataset.repeat/2

## Task

Add a `repeat/2` function to `HfDatasetsEx.Dataset` that repeats the dataset items N times.

## Pre-Implementation Reading

Read these files to understand the existing codebase:

1. `lib/dataset_manager/dataset.ex` - Current Dataset implementation
2. `lib/dataset_manager/iterable_dataset.ex` - IterableDataset for lazy version
3. `test/dataset_manager/dataset_ops_test.exs` - Existing operation tests

## Context

Data augmentation and epoch handling often require repeating a dataset multiple times. This is a simple but frequently needed operation.

## Requirements

### Dataset.repeat/2

```elixir
@doc """
Repeat the dataset N times.

Creates a new dataset with items repeated sequentially N times.
Useful for data augmentation or simulating multiple epochs.

## Examples

    # Triple the dataset
    augmented = Dataset.repeat(dataset, 3)

    # Original: [a, b, c]
    # Result:   [a, b, c, a, b, c, a, b, c]

"""
@spec repeat(t(), pos_integer()) :: t()
```

## File to Modify

`lib/dataset_manager/dataset.ex`

## Implementation

Add to the Dataset Operations section:

```elixir
@doc """
Repeat the dataset N times.

Creates a new dataset with items repeated sequentially N times.
Useful for data augmentation or simulating multiple epochs.

## Examples

    augmented = Dataset.repeat(dataset, 3)
    assert Dataset.num_items(augmented) == Dataset.num_items(dataset) * 3

"""
@spec repeat(t(), pos_integer()) :: t()
def repeat(%__MODULE__{} = dataset, num_times)
    when is_integer(num_times) and num_times > 0 do
  new_items =
    1..num_times
    |> Enum.flat_map(fn _ -> dataset.items end)

  update_items(dataset, new_items)
end
```

### Also add for IterableDataset

```elixir
# In lib/dataset_manager/iterable_dataset.ex

@doc """
Repeat the stream N times.

Creates a new IterableDataset that yields all items N times.
Remains lazy - items are generated on demand.

## Examples

    repeated = IterableDataset.repeat(iterable, 3)

"""
@spec repeat(t(), pos_integer()) :: t()
def repeat(%__MODULE__{} = iterable, num_times)
    when is_integer(num_times) and num_times > 0 do
  new_stream =
    Stream.flat_map(1..num_times, fn _ -> iterable.stream end)

  %{iterable | stream: new_stream}
end
```

## Tests to Add

Add to `test/dataset_manager/dataset_ops_test.exs`:

```elixir
describe "repeat/2" do
  test "repeats items N times" do
    dataset = Dataset.from_list([
      %{"x" => 1},
      %{"x" => 2}
    ])

    repeated = Dataset.repeat(dataset, 3)

    assert Dataset.num_items(repeated) == 6
    assert Enum.map(repeated.items, & &1["x"]) == [1, 2, 1, 2, 1, 2]
  end

  test "repeat(1) returns equivalent dataset" do
    dataset = Dataset.from_list([%{"x" => 1}])
    repeated = Dataset.repeat(dataset, 1)

    assert Dataset.num_items(repeated) == Dataset.num_items(dataset)
    assert repeated.items == dataset.items
  end

  test "handles empty dataset" do
    dataset = Dataset.from_list([])
    repeated = Dataset.repeat(dataset, 5)

    assert Dataset.num_items(repeated) == 0
  end

  test "preserves item structure" do
    dataset = Dataset.from_list([
      %{"a" => 1, "b" => %{nested: true}}
    ])

    repeated = Dataset.repeat(dataset, 2)

    assert Enum.all?(repeated.items, fn item ->
      item["a"] == 1 and item["b"] == %{nested: true}
    end)
  end

  test "updates metadata" do
    dataset = Dataset.from_list([%{"x" => 1}])
    repeated = Dataset.repeat(dataset, 3)

    assert repeated.metadata.total_items == 3
  end
end
```

Add to `test/dataset_manager/iterable_dataset_test.exs`:

```elixir
describe "repeat/2" do
  test "repeats stream N times" do
    iterable = IterableDataset.from_stream(
      Stream.map([1, 2], &%{x: &1}),
      name: "test"
    )

    repeated = IterableDataset.repeat(iterable, 3)
    items = IterableDataset.to_list(repeated)

    assert length(items) == 6
    assert Enum.map(items, & &1.x) == [1, 2, 1, 2, 1, 2]
  end

  test "remains lazy" do
    counter = :counters.new(1, [:atomics])

    iterable = IterableDataset.from_stream(
      Stream.map([1, 2], fn x ->
        :counters.add(counter, 1, 1)
        %{x: x}
      end),
      name: "test"
    )

    repeated = IterableDataset.repeat(iterable, 100)

    # Before consumption
    assert :counters.get(counter, 1) == 0

    # Take only 4 items (2 repetitions)
    IterableDataset.take(repeated, 4)

    # Should have processed only 4 items
    assert :counters.get(counter, 1) == 4
  end
end
```

## Acceptance Criteria

1. `mix test` passes for both Dataset and IterableDataset repeat tests
2. Original dataset/stream is not modified
3. Metadata is properly updated
4. IterableDataset remains lazy
5. `mix credo --strict` has no new issues
6. `mix dialyzer` has no new warnings
