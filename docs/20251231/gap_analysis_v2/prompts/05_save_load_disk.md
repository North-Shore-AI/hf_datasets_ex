# Implementation Prompt: DatasetDict save_to_disk / load_from_disk

## Task

Add `save_to_disk/2` and `load_from_disk/1` functions to persist and restore `DatasetDict` structures in a HuggingFace-compatible format.

## Pre-Implementation Reading

Read these files to understand the existing codebase:

1. `lib/dataset_manager/export.ex` - Export patterns
2. `lib/dataset_manager/export/arrow.ex` - Arrow export (used for data files)
3. `lib/dataset_manager/format/arrow.ex` - Arrow parsing
4. `lib/dataset_manager/dataset_dict.ex` - Current DatasetDict
5. `lib/dataset_manager/dataset.ex` - Dataset structure
6. `lib/dataset_manager/features.ex` - Features serialization

## Context

When working with processed datasets, users need to save their work for later use without re-downloading or re-processing. The disk format should be compatible with Python's `datasets` library for interoperability.

## Requirements

### DatasetDict.save_to_disk/2

```elixir
@doc """
Save a DatasetDict to disk in HuggingFace format.

Creates a directory with Arrow data files and JSON metadata.

## Options

  * `:compression` - Compression for Arrow files (default: :zstd)

## Examples

    :ok = DatasetDict.save_to_disk(dd, "/path/to/dataset")

"""
@spec save_to_disk(t(), Path.t(), keyword()) :: :ok | {:error, term()}
```

### DatasetDict.load_from_disk/2

```elixir
@doc """
Load a DatasetDict from disk.

## Examples

    {:ok, dd} = DatasetDict.load_from_disk("/path/to/dataset")

"""
@spec load_from_disk(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
```

## Disk Format

The format should match HuggingFace's disk format:

```
/path/to/dataset/
├── dataset_dict.json           # {"splits": ["train", "test"]}
├── train/
│   ├── data-00000-of-00001.arrow
│   ├── dataset_info.json
│   └── state.json
└── test/
    ├── data-00000-of-00001.arrow
    ├── dataset_info.json
    └── state.json
```

### dataset_dict.json
```json
{
  "splits": ["train", "test"]
}
```

### dataset_info.json
```json
{
  "features": {
    "text": {"dtype": "string", "_type": "Value"},
    "label": {"names": ["neg", "pos"], "_type": "ClassLabel"}
  },
  "num_rows": 1000
}
```

### state.json
```json
{
  "_data_files": [
    {"filename": "data-00000-of-00001.arrow"}
  ]
}
```

## Files to Create/Modify

1. `lib/dataset_manager/export/disk.ex` (new)
2. `lib/dataset_manager/dataset_dict.ex` (add functions)
3. `test/dataset_manager/export/disk_test.exs` (new)

## Implementation

### Export.Disk module

```elixir
defmodule HfDatasetsEx.Export.Disk do
  @moduledoc """
  Save and load datasets in HuggingFace disk format.
  """

  alias HfDatasetsEx.{Dataset, DatasetDict, Features}
  alias HfDatasetsEx.Export.Arrow

  @doc """
  Save a DatasetDict to disk.
  """
  @spec save_dataset_dict(DatasetDict.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def save_dataset_dict(%DatasetDict{} = dd, path, opts \\ []) do
    File.mkdir_p!(path)

    # Save each split
    results =
      dd.datasets
      |> Enum.map(fn {split_name, dataset} ->
        split_path = Path.join(path, split_name)
        save_dataset(dataset, split_path, opts)
      end)

    # Check for errors
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        # Save dataset_dict.json
        dict_info = %{splits: Map.keys(dd.datasets)}
        dict_path = Path.join(path, "dataset_dict.json")
        File.write!(dict_path, Jason.encode!(dict_info, pretty: true))
        :ok

      error ->
        error
    end
  end

  @doc """
  Save a single Dataset to disk.
  """
  @spec save_dataset(Dataset.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def save_dataset(%Dataset{} = dataset, path, opts \\ []) do
    File.mkdir_p!(path)

    # Save Arrow data
    data_filename = "data-00000-of-00001.arrow"
    data_path = Path.join(path, data_filename)

    with :ok <- Arrow.write(dataset, data_path, opts) do
      # Save dataset_info.json
      info = %{
        features: features_to_json(dataset.features),
        num_rows: Dataset.num_items(dataset),
        size_in_bytes: file_size(data_path)
      }
      info_path = Path.join(path, "dataset_info.json")
      File.write!(info_path, Jason.encode!(info, pretty: true))

      # Save state.json
      state = %{
        _data_files: [%{filename: data_filename}]
      }
      state_path = Path.join(path, "state.json")
      File.write!(state_path, Jason.encode!(state, pretty: true))

      :ok
    end
  end

  @doc """
  Load a DatasetDict from disk.
  """
  @spec load_dataset_dict(Path.t(), keyword()) :: {:ok, DatasetDict.t()} | {:error, term()}
  def load_dataset_dict(path, opts \\ []) do
    dict_path = Path.join(path, "dataset_dict.json")

    with {:ok, content} <- File.read(dict_path),
         {:ok, dict_info} <- Jason.decode(content) do
      splits = dict_info["splits"]

      results =
        splits
        |> Enum.map(fn split_name ->
          split_path = Path.join(path, split_name)
          {split_name, load_dataset(split_path, opts)}
        end)

      # Check for errors
      case Enum.find(results, fn {_, result} -> match?({:error, _}, result) end) do
        nil ->
          datasets =
            results
            |> Enum.map(fn {split, {:ok, ds}} -> {split, ds} end)
            |> Map.new()

          {:ok, DatasetDict.new(datasets)}

        {split, error} ->
          {:error, {:load_split_failed, split, error}}
      end
    end
  end

  @doc """
  Load a single Dataset from disk.
  """
  @spec load_dataset(Path.t(), keyword()) :: {:ok, Dataset.t()} | {:error, term()}
  def load_dataset(path, _opts \\ []) do
    state_path = Path.join(path, "state.json")

    with {:ok, state_content} <- File.read(state_path),
         {:ok, state} <- Jason.decode(state_content) do
      # Get Arrow file from state
      [%{"filename" => filename} | _] = state["_data_files"]
      arrow_path = Path.join(path, filename)

      # Load Arrow data
      with {:ok, items} <- HfDatasetsEx.Format.Arrow.parse(arrow_path) do
        # Load dataset_info for metadata
        info = load_dataset_info(path)

        name = Path.basename(path)
        dataset = Dataset.from_list(items, name: name, metadata: info)

        {:ok, dataset}
      end
    end
  end

  defp features_to_json(nil), do: nil
  defp features_to_json(%Features{} = features) do
    Features.to_map(features)
  end

  defp load_dataset_info(path) do
    info_path = Path.join(path, "dataset_info.json")

    case File.read(info_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, info} -> info
          _ -> %{}
        end
      _ -> %{}
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end
end
```

### DatasetDict additions

```elixir
defmodule HfDatasetsEx.DatasetDict do
  # Add these functions

  alias HfDatasetsEx.Export.Disk

  @doc """
  Save this DatasetDict to disk.
  """
  @spec save_to_disk(t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def save_to_disk(%__MODULE__{} = dd, path, opts \\ []) do
    Disk.save_dataset_dict(dd, path, opts)
  end

  @doc """
  Load a DatasetDict from disk.
  """
  @spec load_from_disk(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def load_from_disk(path, opts \\ []) do
    Disk.load_dataset_dict(path, opts)
  end
end
```

## Tests

```elixir
defmodule HfDatasetsEx.Export.DiskTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.{Dataset, DatasetDict}
  alias HfDatasetsEx.Export.Disk

  @temp_dir "test/tmp/disk_test"

  setup do
    File.rm_rf!(@temp_dir)
    File.mkdir_p!(@temp_dir)

    on_exit(fn ->
      File.rm_rf!(@temp_dir)
    end)

    :ok
  end

  describe "save_dataset_dict/3 and load_dataset_dict/2" do
    test "round-trip preserves data" do
      dd = sample_dataset_dict()
      path = Path.join(@temp_dir, "test_dd")

      assert :ok = Disk.save_dataset_dict(dd, path)
      assert {:ok, loaded} = Disk.load_dataset_dict(path)

      # Check splits
      assert DatasetDict.split_names(loaded) == DatasetDict.split_names(dd)

      # Check data
      for split <- DatasetDict.split_names(dd) do
        original = dd.datasets[split]
        loaded_split = loaded.datasets[split]

        assert Dataset.num_items(loaded_split) == Dataset.num_items(original)
      end
    end

    test "creates correct directory structure" do
      dd = sample_dataset_dict()
      path = Path.join(@temp_dir, "structure_test")

      :ok = Disk.save_dataset_dict(dd, path)

      assert File.exists?(Path.join(path, "dataset_dict.json"))
      assert File.exists?(Path.join(path, "train/data-00000-of-00001.arrow"))
      assert File.exists?(Path.join(path, "train/dataset_info.json"))
      assert File.exists?(Path.join(path, "train/state.json"))
      assert File.exists?(Path.join(path, "test/data-00000-of-00001.arrow"))
    end

    test "dataset_dict.json contains split names" do
      dd = sample_dataset_dict()
      path = Path.join(@temp_dir, "json_test")

      :ok = Disk.save_dataset_dict(dd, path)

      content = File.read!(Path.join(path, "dataset_dict.json"))
      {:ok, info} = Jason.decode(content)

      assert Enum.sort(info["splits"]) == ["test", "train"]
    end
  end

  describe "save_dataset/3 and load_dataset/2" do
    test "round-trip preserves data" do
      dataset = Dataset.from_list([
        %{"x" => 1, "y" => "a"},
        %{"x" => 2, "y" => "b"}
      ])
      path = Path.join(@temp_dir, "single_ds")

      assert :ok = Disk.save_dataset(dataset, path)
      assert {:ok, loaded} = Disk.load_dataset(path)

      assert Dataset.num_items(loaded) == 2
      assert Enum.at(loaded.items, 0)["x"] == 1
    end

    test "handles empty dataset" do
      dataset = Dataset.from_list([])
      path = Path.join(@temp_dir, "empty_ds")

      assert :ok = Disk.save_dataset(dataset, path)
      assert {:ok, loaded} = Disk.load_dataset(path)

      assert Dataset.num_items(loaded) == 0
    end
  end

  describe "error handling" do
    test "load_dataset_dict returns error for missing path" do
      assert {:error, _} = Disk.load_dataset_dict("/nonexistent/path")
    end

    test "load_dataset returns error for missing state.json" do
      path = Path.join(@temp_dir, "no_state")
      File.mkdir_p!(path)

      assert {:error, _} = Disk.load_dataset(path)
    end
  end

  defp sample_dataset_dict do
    train = Dataset.from_list([
      %{"text" => "hello", "label" => 0},
      %{"text" => "world", "label" => 1}
    ])
    test = Dataset.from_list([
      %{"text" => "foo", "label" => 0}
    ])

    DatasetDict.new(%{"train" => train, "test" => test})
  end
end
```

## Acceptance Criteria

1. `mix test test/dataset_manager/export/disk_test.exs` passes
2. Round-trip save/load preserves all data
3. Directory structure matches HuggingFace format
4. Works with empty datasets
5. Error handling for missing files
6. `mix credo --strict` has no new issues
7. `mix dialyzer` has no new warnings
