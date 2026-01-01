# Quick Implementation Guide

## Phase 1: Quick Wins (1-2 hours each)

### 1. DatasetDict.map/filter

Add to `lib/dataset_manager/dataset_dict.ex`:

```elixir
@spec map(t(), (map() -> map()), keyword()) :: t()
def map(%__MODULE__{datasets: datasets} = dd, fun, opts \\ []) do
  new_datasets = Map.new(datasets, fn {k, v} -> {k, Dataset.map(v, fun, opts)} end)
  %{dd | datasets: new_datasets}
end

@spec filter(t(), (map() -> boolean()), keyword()) :: t()
def filter(%__MODULE__{datasets: datasets} = dd, predicate, opts \\ []) do
  new_datasets = Map.new(datasets, fn {k, v} -> {k, Dataset.filter(v, predicate, opts)} end)
  %{dd | datasets: new_datasets}
end
```

### 2. IterableDataset.concatenate

Add to `lib/dataset_manager/iterable_dataset.ex`:

```elixir
@spec concatenate([t()]) :: t()
def concatenate([single]), do: single
def concatenate(datasets) do
  streams = Enum.map(datasets, & &1.stream)
  %__MODULE__{stream: Stream.concat(streams), name: "concatenated", info: hd(datasets).info}
end
```

### 3. Dataset.repeat

Add to `lib/dataset_manager/dataset.ex`:

```elixir
@spec repeat(t(), pos_integer()) :: t()
def repeat(%__MODULE__{} = dataset, n) when is_integer(n) and n > 0 do
  new_items = Enum.flat_map(1..n, fn _ -> dataset.items end)
  update_items(dataset, new_items)
end
```

---

## Phase 2: Medium Tasks (Half day each)

### 4. Format.ImageFolder

Create `lib/dataset_manager/format/imagefolder.ex`:

```elixir
defmodule HfDatasetsEx.Format.ImageFolder do
  @extensions ~w(.jpg .jpeg .png .gif .bmp .webp)

  def parse(path, opts \\ []) do
    decode = Keyword.get(opts, :decode, false)

    items =
      Path.join(path, "*/*")
      |> Path.wildcard()
      |> Enum.filter(&valid_image?/1)
      |> Enum.map(&to_item(&1, decode))

    {:ok, items}
  end

  defp valid_image?(p), do: Path.extname(p) |> String.downcase() in @extensions

  defp to_item(path, decode) do
    label = Path.dirname(path) |> Path.basename()
    bytes = if decode, do: File.read!(path), else: nil
    %{"image" => %{"path" => path, "bytes" => bytes}, "label" => label}
  end
end
```

### 5. Export.Disk

See `prompts/05_save_load_disk.md` for full implementation.

---

## Phase 3: Complex Tasks (Full day each)

### 6. IterableDataset.interleave

See `prompts/06_iterable_interleave.md` for full implementation.

---

## Testing Checklist

After each implementation:

```bash
# Run tests
mix test test/dataset_manager/dataset_dict_test.exs
mix test test/dataset_manager/iterable_dataset_test.exs
mix test test/dataset_manager/dataset_ops_test.exs

# Code quality
mix format
mix credo --strict
mix dialyzer
```

---

## Priority Order

1. **DatasetDict.map/filter** - Highest value, lowest effort
2. **IterableDataset.concatenate** - Common use case
3. **Dataset.repeat** - Simple augmentation
4. **Format.ImageFolder** - Vision dataset support
5. **Export.Disk save/load** - Persistence for DatasetDict
6. **IterableDataset.interleave** - Multi-source training

---

## Commit Messages

```
feat(dataset_dict): add map/filter operations across splits

feat(iterable): add concatenate for combining streams

feat(dataset): add repeat operation for data augmentation

feat(format): add ImageFolder format for directory-based datasets

feat(export): add save_to_disk/load_from_disk for DatasetDict

feat(iterable): add interleave for probability-based mixing
```
