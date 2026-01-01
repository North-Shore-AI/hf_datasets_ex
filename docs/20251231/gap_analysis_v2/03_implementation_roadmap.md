# Implementation Roadmap

## Phase 1: Quick Wins (Low Complexity, High Value)

These can be implemented in a single session each.

### 1.1 DatasetDict.map/3 and filter/3

**Files to modify**:
- `lib/dataset_manager/dataset_dict.ex`
- `test/dataset_manager/dataset_dict_test.exs`

**Implementation**:
```elixir
defmodule HfDatasetsEx.DatasetDict do
  # Add to existing module

  @doc """
  Apply a map function to all splits.
  """
  @spec map(t(), (map() -> map()), keyword()) :: t()
  def map(%__MODULE__{datasets: datasets} = dd, fun, opts \\ []) do
    new_datasets =
      Map.new(datasets, fn {split, dataset} ->
        {split, Dataset.map(dataset, fun, opts)}
      end)

    %{dd | datasets: new_datasets}
  end

  @doc """
  Filter all splits with a predicate.
  """
  @spec filter(t(), (map() -> boolean()), keyword()) :: t()
  def filter(%__MODULE__{datasets: datasets} = dd, predicate, opts \\ []) do
    new_datasets =
      Map.new(datasets, fn {split, dataset} ->
        {split, Dataset.filter(dataset, predicate, opts)}
      end)

    %{dd | datasets: new_datasets}
  end
end
```

---

### 1.2 IterableDataset.concatenate/1

**Files to modify**:
- `lib/dataset_manager/iterable_dataset.ex`
- `test/dataset_manager/iterable_dataset_test.exs`

**Implementation**:
```elixir
defmodule HfDatasetsEx.IterableDataset do
  @doc """
  Concatenate multiple IterableDatasets sequentially.
  """
  @spec concatenate([t()]) :: t()
  def concatenate([first | rest] = _datasets) do
    streams = Enum.map([first | rest], & &1.stream)
    combined = Stream.concat(streams)

    %__MODULE__{
      stream: combined,
      name: first.name <> "_concatenated",
      info: first.info
    }
  end
end
```

---

### 1.3 Dataset.repeat/2

**Files to modify**:
- `lib/dataset_manager/dataset.ex`
- `test/dataset_manager/dataset_ops_test.exs`

**Implementation**:
```elixir
defmodule HfDatasetsEx.Dataset do
  @doc """
  Repeat dataset N times.
  """
  @spec repeat(t(), pos_integer()) :: t()
  def repeat(%__MODULE__{} = dataset, num_times) when is_integer(num_times) and num_times > 0 do
    new_items =
      dataset.items
      |> List.duplicate(num_times)
      |> List.flatten()

    update_items(dataset, new_items)
  end
end
```

---

### 1.4 Format.ImageFolder

**Files to create**:
- `lib/dataset_manager/format/imagefolder.ex`
- `test/dataset_manager/format/imagefolder_test.exs`

**Implementation**:
```elixir
defmodule HfDatasetsEx.Format.ImageFolder do
  @moduledoc """
  Load datasets from directory structure where subdirectories are class labels.
  """

  @image_extensions ~w(.jpg .jpeg .png .gif .bmp .webp)

  @spec parse(Path.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def parse(path, opts \\ []) do
    decode = Keyword.get(opts, :decode, false)

    items =
      path
      |> Path.join("*/*")
      |> Path.wildcard()
      |> Enum.filter(&image_file?/1)
      |> Enum.map(&to_item(&1, decode))

    {:ok, items}
  end

  defp image_file?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext in @image_extensions
  end

  defp to_item(file_path, decode) do
    label = file_path |> Path.dirname() |> Path.basename()

    image = %{
      "path" => file_path,
      "bytes" => if(decode, do: File.read!(file_path), else: nil)
    }

    %{"image" => image, "label" => label}
  end
end
```

---

## Phase 2: Core Infrastructure (Medium Complexity)

### 2.1 DatasetDict.save_to_disk/2 and load_from_disk/2

**Files to create/modify**:
- `lib/dataset_manager/dataset_dict.ex`
- `lib/dataset_manager/export/disk.ex`
- `test/dataset_manager/export/disk_test.exs`

**Implementation**:
```elixir
defmodule HfDatasetsEx.Export.Disk do
  @moduledoc """
  Save and load datasets in HuggingFace disk format.
  """

  alias HfDatasetsEx.{Dataset, DatasetDict, Features}
  alias HfDatasetsEx.Export.Arrow

  @spec save_dataset_dict(DatasetDict.t(), Path.t()) :: :ok | {:error, term()}
  def save_dataset_dict(%DatasetDict{} = dd, path) do
    File.mkdir_p!(path)

    # Save each split
    for {split_name, dataset} <- dd.datasets do
      split_path = Path.join(path, split_name)
      save_dataset(dataset, split_path)
    end

    # Save dataset_dict.json
    dict_info = %{
      splits: Map.keys(dd.datasets)
    }
    File.write!(Path.join(path, "dataset_dict.json"), Jason.encode!(dict_info))

    :ok
  end

  @spec save_dataset(Dataset.t(), Path.t()) :: :ok | {:error, term()}
  def save_dataset(%Dataset{} = dataset, path) do
    File.mkdir_p!(path)

    # Save data as Arrow
    data_path = Path.join(path, "data-00000-of-00001.arrow")
    Arrow.write(dataset, data_path)

    # Save dataset_info.json
    info = %{
      features: if(dataset.features, do: Features.to_map(dataset.features), else: nil),
      num_rows: Dataset.num_items(dataset)
    }
    File.write!(Path.join(path, "dataset_info.json"), Jason.encode!(info))

    # Save state.json
    state = %{
      _data_files: [%{filename: "data-00000-of-00001.arrow"}]
    }
    File.write!(Path.join(path, "state.json"), Jason.encode!(state))

    :ok
  end

  @spec load_dataset_dict(Path.t()) :: {:ok, DatasetDict.t()} | {:error, term()}
  def load_dataset_dict(path) do
    dict_path = Path.join(path, "dataset_dict.json")

    with {:ok, content} <- File.read(dict_path),
         {:ok, dict_info} <- Jason.decode(content) do
      datasets =
        dict_info["splits"]
        |> Enum.map(fn split_name ->
          split_path = Path.join(path, split_name)
          {:ok, dataset} = load_dataset(split_path)
          {split_name, dataset}
        end)
        |> Map.new()

      {:ok, DatasetDict.new(datasets)}
    end
  end

  @spec load_dataset(Path.t()) :: {:ok, Dataset.t()} | {:error, term()}
  def load_dataset(path) do
    # Find Arrow file
    arrow_pattern = Path.join(path, "*.arrow")

    case Path.wildcard(arrow_pattern) do
      [arrow_path | _] ->
        # Load via Arrow format
        HfDatasetsEx.Format.Arrow.parse(arrow_path)
        |> case do
          {:ok, items} -> {:ok, Dataset.from_list(items)}
          error -> error
        end

      [] ->
        {:error, {:no_data_file, path}}
    end
  end
end
```

---

### 2.2 IterableDataset.interleave/2

**Files to modify**:
- `lib/dataset_manager/iterable_dataset.ex`
- `test/dataset_manager/iterable_dataset_test.exs`

**Implementation**:
```elixir
defmodule HfDatasetsEx.IterableDataset do
  @doc """
  Interleave items from multiple IterableDatasets.

  ## Options

    * `:probabilities` - Selection probabilities (must sum to 1.0)
    * `:seed` - Random seed for reproducibility
    * `:stopping_strategy` - :first_exhausted or :all_exhausted

  """
  @spec interleave([t()], keyword()) :: t()
  def interleave(datasets, opts \\ []) do
    probs = Keyword.get(opts, :probabilities, uniform_probs(length(datasets)))
    seed = Keyword.get(opts, :seed)
    stopping = Keyword.get(opts, :stopping_strategy, :first_exhausted)

    stream = Stream.resource(
      fn ->
        if seed, do: :rand.seed(:exsss, {seed, seed, seed})
        # Initialize iterators
        iterators = Enum.map(datasets, fn ds ->
          {Enumerable.reduce(ds.stream, {:cont, []}, fn x, acc -> {:suspend, [x | acc]} end), []}
        end)
        {iterators, probs, stopping}
      end,
      fn {iterators, probs, stopping} ->
        # Select dataset based on probabilities
        idx = weighted_random_index(probs)
        {iterator_state, buffer} = Enum.at(iterators, idx)

        case next_from_iterator(iterator_state, buffer) do
          {:ok, item, new_state, new_buffer} ->
            new_iterators = List.replace_at(iterators, idx, {new_state, new_buffer})
            {[item], {new_iterators, probs, stopping}}

          :exhausted ->
            case stopping do
              :first_exhausted ->
                {:halt, nil}
              :all_exhausted ->
                # Remove exhausted, adjust probabilities
                remaining = remove_exhausted(iterators, probs, idx)
                if remaining == [] do
                  {:halt, nil}
                else
                  {new_iterators, new_probs} = remaining
                  {[], {new_iterators, new_probs, stopping}}
                end
            end
        end
      end,
      fn _ -> :ok end
    )

    %__MODULE__{
      stream: stream,
      name: "interleaved",
      info: hd(datasets).info
    }
  end

  defp uniform_probs(n), do: List.duplicate(1.0 / n, n)

  defp weighted_random_index(probs) do
    r = :rand.uniform()
    probs
    |> Enum.with_index()
    |> Enum.reduce_while(0.0, fn {p, idx}, acc ->
      new_acc = acc + p
      if r <= new_acc, do: {:halt, idx}, else: {:cont, new_acc}
    end)
  end

  # ... helper functions
end
```

---

### 2.3 Dataset.with_transform/3 and set_transform/3

**Files to modify**:
- `lib/dataset_manager/dataset.ex`
- `test/dataset_manager/dataset_ops_test.exs`

**Implementation**:
```elixir
defmodule HfDatasetsEx.Dataset do
  # Add to struct:
  # transform: (map() -> map()) | nil
  # transform_columns: [String.t()] | nil

  @doc """
  Set an on-access transform (modifies dataset).
  """
  @spec set_transform(t(), (map() -> map()), keyword()) :: t()
  def set_transform(%__MODULE__{} = dataset, transform, opts \\ []) do
    columns = Keyword.get(opts, :columns)
    %{dataset | transform: transform, transform_columns: columns}
  end

  @doc """
  Return copy with transform (doesn't modify original).
  """
  @spec with_transform(t(), (map() -> map()), keyword()) :: t()
  def with_transform(%__MODULE__{} = dataset, transform, opts \\ []) do
    set_transform(dataset, transform, opts)
  end

  # Update Enumerable implementation to apply transform
  defimpl Enumerable do
    def reduce(%Dataset{items: items, transform: nil} = dataset, acc, fun) do
      # ... existing implementation
    end

    def reduce(%Dataset{items: items, transform: transform} = dataset, acc, fun) do
      items
      |> Stream.map(transform)
      |> Stream.map(&apply_format(&1, dataset))
      |> Enumerable.reduce(acc, fun)
    end
  end
end
```

---

## Phase 3: Format Extensions

### 3.1 Format.XML

**Files to create**:
- `lib/dataset_manager/format/xml.ex`
- `test/dataset_manager/format/xml_test.exs`

**Dependencies**: Add `sweet_xml` to mix.exs

**Implementation**:
```elixir
defmodule HfDatasetsEx.Format.XML do
  @moduledoc """
  Parse XML files into datasets.
  """

  import SweetXml

  @spec parse(Path.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def parse(path, opts \\ []) do
    row_tag = Keyword.get(opts, :row_tag, "row")

    try do
      items =
        path
        |> File.read!()
        |> xpath(~x"//#{row_tag}"l)
        |> Enum.map(&xml_to_map/1)

      {:ok, items}
    rescue
      e -> {:error, {:parse_error, e}}
    end
  end

  defp xml_to_map(node) do
    node
    |> xpath(~x"./*"l)
    |> Enum.map(fn child ->
      name = xpath(child, ~x"name(.)"s)
      value = xpath(child, ~x"./text()"s)
      {name, value}
    end)
    |> Map.new()
  end
end
```

---

### 3.2 Format.SQL

**Files to create**:
- `lib/dataset_manager/format/sql.ex`
- `test/dataset_manager/format/sql_test.exs`

**Dependencies**: `ecto_sql` (optional)

**Implementation**:
```elixir
defmodule HfDatasetsEx.Format.SQL do
  @moduledoc """
  Load data from SQL databases via Ecto.
  """

  @spec from_query(module(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def from_query(repo, sql, opts \\ []) do
    params = Keyword.get(opts, :params, [])

    case Ecto.Adapters.SQL.query(repo, sql, params) do
      {:ok, %{columns: columns, rows: rows}} ->
        items = Enum.map(rows, fn row ->
          columns
          |> Enum.zip(row)
          |> Map.new()
        end)
        {:ok, items}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec from_table(module(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def from_table(repo, table_name, opts \\ []) do
    # Sanitize table name to prevent SQL injection
    if valid_identifier?(table_name) do
      from_query(repo, "SELECT * FROM #{table_name}", opts)
    else
      {:error, :invalid_table_name}
    end
  end

  defp valid_identifier?(name) do
    Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, name)
  end
end
```

---

## Phase 4: Advanced Features (P3)

These are lower priority and can be deferred:

1. **Index.Qdrant** - REST API integration for vector search
2. **Index.Elasticsearch** - Full-text search integration
3. **Format.WebDataset** - Tar archive loading
4. **Feature Types: Video, Pdf, Nifti** - Specialized media
5. **Index.FAISS** - Native NIF for performance

---

## Testing Strategy

Each implementation should include:

1. **Unit Tests**: Basic functionality
2. **Edge Cases**: Empty inputs, nil values, large datasets
3. **Integration Tests**: Real files, real databases (tagged)
4. **Property Tests**: StreamData for randomized testing

Example test structure:
```elixir
defmodule HfDatasetsEx.Format.ImageFolderTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Format.ImageFolder

  @fixture_path "test/fixtures/imagefolder"

  setup do
    # Create test directory structure
    :ok
  end

  describe "parse/2" do
    test "loads images with labels from subdirectories" do
      {:ok, items} = ImageFolder.parse(@fixture_path)

      assert length(items) > 0
      assert Enum.all?(items, &Map.has_key?(&1, "image"))
      assert Enum.all?(items, &Map.has_key?(&1, "label"))
    end

    test "handles empty directories" do
      {:ok, items} = ImageFolder.parse("test/fixtures/empty")
      assert items == []
    end
  end
end
```

---

## Dependency Updates

Add to `mix.exs` as needed:

```elixir
defp deps do
  [
    # Existing deps...

    # Optional new deps
    {:sweet_xml, "~> 0.7", optional: true},
    {:ecto_sql, "~> 3.10", optional: true}
  ]
end
```

---

## Success Metrics

- All tests pass: `mix test`
- No warnings: `mix compile --warnings-as-errors`
- No issues: `mix credo --strict`
- No type errors: `mix dialyzer`
- Coverage > 80%: `mix coveralls`
