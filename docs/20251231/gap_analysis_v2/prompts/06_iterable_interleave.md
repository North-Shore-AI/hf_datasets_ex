# Implementation Prompt: IterableDataset.interleave/2

## Task

Add an `interleave/2` function to `HfDatasetsEx.IterableDataset` that interleaves items from multiple streaming datasets based on probabilities.

## Pre-Implementation Reading

Read these files to understand the existing codebase:

1. `lib/dataset_manager/iterable_dataset.ex` - Current implementation
2. `lib/prng/pcg64.ex` - PRNG for reproducibility (optional, can use :rand)
3. `test/dataset_manager/iterable_dataset_test.exs` - Test patterns

## Context

When training on multiple data sources, it's often beneficial to mix items from different datasets. For example, mixing 70% English data with 30% translated data. This should remain lazy/streaming.

## Requirements

### IterableDataset.interleave/2

```elixir
@doc """
Interleave items from multiple IterableDatasets.

Items are selected randomly based on the provided probabilities.
This is useful for mixing multiple data sources during training.

## Options

  * `:probabilities` - Selection probabilities (must sum to 1.0).
    Default: uniform distribution.
  * `:seed` - Random seed for reproducibility
  * `:stopping_strategy` - When to stop:
    - `:first_exhausted` (default) - Stop when any dataset is exhausted
    - `:all_exhausted` - Continue until all datasets are exhausted (oversampling)
    - `:all_exhausted_without_replacement` - Sample each item exactly once

## Examples

    # Uniform mixing
    mixed = IterableDataset.interleave([ds1, ds2, ds3])

    # Weighted mixing (70% from ds1, 30% from ds2)
    mixed = IterableDataset.interleave([ds1, ds2],
      probabilities: [0.7, 0.3],
      seed: 42
    )

"""
@spec interleave([t()], keyword()) :: t()
```

## File to Modify

`lib/dataset_manager/iterable_dataset.ex`

## Implementation

```elixir
defmodule HfDatasetsEx.IterableDataset do
  # Add these functions

  @doc """
  Interleave items from multiple IterableDatasets.
  """
  @spec interleave([t()], keyword()) :: t()
  def interleave([], _opts), do: from_stream(Stream.map([], & &1), name: "empty")

  def interleave([single], _opts), do: single

  def interleave(datasets, opts \\ []) do
    n = length(datasets)
    probs = Keyword.get(opts, :probabilities, uniform_probabilities(n))
    seed = Keyword.get(opts, :seed)
    stopping = Keyword.get(opts, :stopping_strategy, :first_exhausted)

    # Validate probabilities
    unless length(probs) == n and abs(Enum.sum(probs) - 1.0) < 0.001 do
      raise ArgumentError,
        "probabilities must have same length as datasets and sum to 1.0"
    end

    stream = interleave_stream(datasets, probs, seed, stopping)

    %__MODULE__{
      stream: stream,
      name: "interleaved",
      info: merge_info(datasets)
    }
  end

  defp uniform_probabilities(n) do
    List.duplicate(1.0 / n, n)
  end

  defp interleave_stream(datasets, probs, seed, stopping) do
    Stream.resource(
      fn -> init_interleave_state(datasets, probs, seed, stopping) end,
      &next_interleave_item/1,
      fn _ -> :ok end
    )
  end

  defp init_interleave_state(datasets, probs, seed, stopping) do
    if seed, do: :rand.seed(:exsss, {seed, seed, seed})

    # Convert each dataset stream to a continuation
    continuations =
      datasets
      |> Enum.with_index()
      |> Enum.map(fn {ds, idx} ->
        {idx, stream_continuation(ds.stream)}
      end)
      |> Map.new()

    %{
      continuations: continuations,
      probabilities: probs,
      stopping: stopping,
      active_indices: Enum.to_list(0..(length(datasets) - 1))
    }
  end

  # Get a continuation that can yield one item at a time
  defp stream_continuation(stream) do
    reducer = fn item, _acc -> {:suspend, item} end

    case Enumerable.reduce(stream, {:cont, nil}, reducer) do
      {:suspended, item, cont} -> {:active, item, cont}
      {:halted, _} -> :exhausted
      {:done, _} -> :exhausted
    end
  end

  defp next_interleave_item(%{active_indices: []} = _state) do
    {:halt, nil}
  end

  defp next_interleave_item(state) do
    # Select a dataset based on probabilities
    idx = weighted_random_select(state.active_indices, state.probabilities)

    case Map.get(state.continuations, idx) do
      {:active, item, cont} ->
        # Get next item from continuation
        new_cont = advance_continuation(cont)
        new_continuations = Map.put(state.continuations, idx, new_cont)
        new_state = %{state | continuations: new_continuations}

        # Check if this one exhausted
        new_state = maybe_handle_exhaustion(new_state, idx, new_cont)

        {[item], new_state}

      :exhausted ->
        # This shouldn't happen if active_indices is correct
        # but handle it gracefully
        new_state = remove_index(state, idx)
        next_interleave_item(new_state)
    end
  end

  defp advance_continuation(cont) do
    case cont.({:cont, nil}) do
      {:suspended, item, new_cont} -> {:active, item, new_cont}
      {:halted, _} -> :exhausted
      {:done, _} -> :exhausted
    end
  end

  defp weighted_random_select(indices, all_probs) do
    # Get probabilities for active indices and normalize
    active_probs =
      indices
      |> Enum.map(&Enum.at(all_probs, &1))

    sum = Enum.sum(active_probs)
    normalized = Enum.map(active_probs, &(&1 / sum))

    # Weighted random selection
    r = :rand.uniform()
    select_by_cumulative(Enum.zip(indices, normalized), r, 0.0)
  end

  defp select_by_cumulative([{idx, _prob}], _r, _cum), do: idx

  defp select_by_cumulative([{idx, prob} | rest], r, cum) do
    new_cum = cum + prob
    if r <= new_cum do
      idx
    else
      select_by_cumulative(rest, r, new_cum)
    end
  end

  defp maybe_handle_exhaustion(state, idx, :exhausted) do
    case state.stopping do
      :first_exhausted ->
        # Signal to stop
        %{state | active_indices: []}

      :all_exhausted ->
        # Remove this index and continue
        remove_index(state, idx)
    end
  end

  defp maybe_handle_exhaustion(state, _idx, _cont), do: state

  defp remove_index(state, idx) do
    %{state | active_indices: List.delete(state.active_indices, idx)}
  end

  defp merge_info(datasets) do
    datasets
    |> Enum.map(& &1.info)
    |> Enum.reduce(%{}, &Map.merge(&2, &1))
  end
end
```

## Tests

Add to `test/dataset_manager/iterable_dataset_test.exs`:

```elixir
describe "interleave/2" do
  test "interleaves items from multiple datasets" do
    ds1 = IterableDataset.from_stream(
      Stream.map(1..100, &%{source: :ds1, x: &1}),
      name: "ds1"
    )
    ds2 = IterableDataset.from_stream(
      Stream.map(1..100, &%{source: :ds2, x: &1}),
      name: "ds2"
    )

    interleaved = IterableDataset.interleave([ds1, ds2], seed: 42)
    items = IterableDataset.take(interleaved, 20)

    sources = Enum.map(items, & &1.source)

    # Should have items from both sources
    assert :ds1 in sources
    assert :ds2 in sources
  end

  test "respects probabilities" do
    ds1 = IterableDataset.from_stream(
      Stream.map(1..1000, &%{source: :ds1, x: &1}),
      name: "ds1"
    )
    ds2 = IterableDataset.from_stream(
      Stream.map(1..1000, &%{source: :ds2, x: &1}),
      name: "ds2"
    )

    # 90% from ds1, 10% from ds2
    interleaved = IterableDataset.interleave([ds1, ds2],
      probabilities: [0.9, 0.1],
      seed: 42
    )

    items = IterableDataset.take(interleaved, 100)
    ds1_count = Enum.count(items, &(&1.source == :ds1))

    # Should be roughly 90% (allow some variance)
    assert ds1_count > 70 and ds1_count < 100
  end

  test "seed provides reproducibility" do
    make_datasets = fn ->
      ds1 = IterableDataset.from_stream(
        Stream.map(1..50, &%{source: :ds1, x: &1}),
        name: "ds1"
      )
      ds2 = IterableDataset.from_stream(
        Stream.map(1..50, &%{source: :ds2, x: &1}),
        name: "ds2"
      )
      [ds1, ds2]
    end

    result1 =
      make_datasets.()
      |> IterableDataset.interleave(seed: 42)
      |> IterableDataset.take(20)

    result2 =
      make_datasets.()
      |> IterableDataset.interleave(seed: 42)
      |> IterableDataset.take(20)

    assert result1 == result2
  end

  test "first_exhausted stops when any dataset ends" do
    ds1 = IterableDataset.from_stream(
      Stream.map(1..5, &%{source: :ds1, x: &1}),
      name: "ds1"
    )
    ds2 = IterableDataset.from_stream(
      Stream.map(1..100, &%{source: :ds2, x: &1}),
      name: "ds2"
    )

    interleaved = IterableDataset.interleave([ds1, ds2],
      stopping_strategy: :first_exhausted,
      seed: 42
    )

    items = IterableDataset.to_list(interleaved)

    # Should stop relatively early (when ds1 is exhausted)
    assert length(items) < 20
  end

  test "all_exhausted continues until all datasets end" do
    ds1 = IterableDataset.from_stream(
      Stream.map(1..5, &%{source: :ds1, x: &1}),
      name: "ds1"
    )
    ds2 = IterableDataset.from_stream(
      Stream.map(1..10, &%{source: :ds2, x: &1}),
      name: "ds2"
    )

    interleaved = IterableDataset.interleave([ds1, ds2],
      stopping_strategy: :all_exhausted,
      seed: 42
    )

    items = IterableDataset.to_list(interleaved)

    # Should get all items from both
    assert length(items) == 15
  end

  test "handles single dataset" do
    ds = IterableDataset.from_stream(
      Stream.map(1..5, &%{x: &1}),
      name: "single"
    )

    interleaved = IterableDataset.interleave([ds])
    items = IterableDataset.to_list(interleaved)

    assert length(items) == 5
  end

  test "handles empty list" do
    interleaved = IterableDataset.interleave([])
    items = IterableDataset.to_list(interleaved)

    assert items == []
  end

  test "validates probabilities" do
    ds1 = IterableDataset.from_stream(Stream.map(1..5, & &1), name: "ds1")
    ds2 = IterableDataset.from_stream(Stream.map(1..5, & &1), name: "ds2")

    # Wrong length
    assert_raise ArgumentError, fn ->
      IterableDataset.interleave([ds1, ds2], probabilities: [0.5])
    end

    # Doesn't sum to 1
    assert_raise ArgumentError, fn ->
      IterableDataset.interleave([ds1, ds2], probabilities: [0.3, 0.3])
    end
  end
end
```

## Acceptance Criteria

1. `mix test test/dataset_manager/iterable_dataset_test.exs` passes
2. Interleaving respects probability weights
3. Seed provides reproducible results
4. Both stopping strategies work correctly
5. Remains lazy (doesn't materialize streams upfront)
6. `mix credo --strict` has no new issues
7. `mix dialyzer` has no new warnings
