# Implementation Prompt: Format.ImageFolder

## Task

Create a new format parser `HfDatasetsEx.Format.ImageFolder` that loads image datasets from directory structures where subdirectories represent class labels.

## Pre-Implementation Reading

Read these files to understand the existing codebase:

1. `lib/dataset_manager/format/csv.ex` - Pattern for format parsers
2. `lib/dataset_manager/format/jsonl.ex` - Another format parser example
3. `lib/dataset_manager/dataset.ex` - See from_csv, from_json patterns
4. `lib/dataset_manager/features/image.ex` - Image feature type
5. `test/dataset_manager/format/csv_test.exs` - Test patterns

## Context

ImageFolder is one of the most common patterns for organizing image classification datasets. The structure is:

```
dataset/
├── cat/
│   ├── 001.jpg
│   ├── 002.jpg
│   └── ...
├── dog/
│   ├── 001.jpg
│   ├── 002.jpg
│   └── ...
└── bird/
    └── ...
```

Each subdirectory name becomes the label for images within it.

## Requirements

### Format.ImageFolder.parse/2

```elixir
@doc """
Parse an ImageFolder directory structure into a dataset.

Returns a list of maps with "image" and "label" keys.

## Options

  * `:decode` - Whether to read image bytes (default: false)
  * `:extensions` - List of valid extensions (default: common image formats)

## Examples

    {:ok, items} = Format.ImageFolder.parse("/path/to/dataset")

    # Returns:
    [
      %{
        "image" => %{"path" => "/path/to/dataset/cat/001.jpg", "bytes" => nil},
        "label" => "cat"
      },
      ...
    ]

    # With decoding:
    {:ok, items} = Format.ImageFolder.parse("/path/to/dataset", decode: true)
    # "bytes" will contain the raw image binary

"""
@spec parse(Path.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
```

## Files to Create

1. `lib/dataset_manager/format/imagefolder.ex`
2. `test/dataset_manager/format/imagefolder_test.exs`
3. `test/fixtures/imagefolder/` (test directory structure)

## Implementation

```elixir
defmodule HfDatasetsEx.Format.ImageFolder do
  @moduledoc """
  Load image datasets from directory structure.

  Expects a directory where each subdirectory is a class label
  containing image files.

  ## Directory Structure

      dataset/
      ├── cat/
      │   ├── 001.jpg
      │   └── 002.png
      └── dog/
          ├── 001.jpg
          └── 002.png

  ## Example

      {:ok, items} = ImageFolder.parse("./dataset")
      dataset = Dataset.from_list(items, name: "my_images")

  """

  @default_extensions ~w(.jpg .jpeg .png .gif .bmp .webp .tiff .tif)

  @type parse_opts :: [
    decode: boolean(),
    extensions: [String.t()]
  ]

  @doc """
  Parse an ImageFolder directory into dataset items.
  """
  @spec parse(Path.t(), parse_opts()) :: {:ok, [map()]} | {:error, term()}
  def parse(path, opts \\ []) do
    decode = Keyword.get(opts, :decode, false)
    extensions = Keyword.get(opts, :extensions, @default_extensions)

    if File.dir?(path) do
      items =
        path
        |> list_class_directories()
        |> Enum.flat_map(&list_class_images(&1, extensions))
        |> Enum.map(&to_item(&1, decode))
        |> Enum.sort_by(& &1["label"])

      {:ok, items}
    else
      {:error, {:not_a_directory, path}}
    end
  end

  @doc """
  Parse as a stream for memory efficiency.
  """
  @spec parse_stream(Path.t(), parse_opts()) :: Enumerable.t()
  def parse_stream(path, opts \\ []) do
    decode = Keyword.get(opts, :decode, false)
    extensions = Keyword.get(opts, :extensions, @default_extensions)

    path
    |> list_class_directories()
    |> Stream.flat_map(&list_class_images(&1, extensions))
    |> Stream.map(&to_item(&1, decode))
  end

  # List immediate subdirectories (class labels)
  defp list_class_directories(path) do
    path
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
  end

  # List image files in a class directory
  defp list_class_images(class_dir, extensions) do
    label = Path.basename(class_dir)
    ext_pattern = "{" <> Enum.join(extensions, ",") <> "}"

    class_dir
    |> Path.join("*" <> ext_pattern)
    |> Path.wildcard()
    |> Enum.map(&{&1, label})
  end

  # Convert file path to dataset item
  defp to_item({file_path, label}, decode) do
    image = %{
      "path" => file_path,
      "bytes" => if(decode, do: read_file(file_path), else: nil)
    }

    %{
      "image" => image,
      "label" => label
    }
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, bytes} -> bytes
      {:error, _} -> nil
    end
  end
end
```

## Integration with Dataset

Add convenience function to Dataset:

```elixir
# In lib/dataset_manager/dataset.ex

@doc """
Create a dataset from an ImageFolder directory.

## Options

  * `:decode` - Read image bytes (default: false)
  * `:name` - Dataset name (default: directory basename)

## Examples

    {:ok, dataset} = Dataset.from_imagefolder("./data/train")

"""
@spec from_imagefolder(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
def from_imagefolder(path, opts \\ []) do
  name = Keyword.get(opts, :name, Path.basename(path))

  with {:ok, items} <- HfDatasetsEx.Format.ImageFolder.parse(path, opts) do
    {:ok, from_list(items, name: name)}
  end
end
```

## Tests

```elixir
defmodule HfDatasetsEx.Format.ImageFolderTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Format.ImageFolder

  @fixture_path "test/fixtures/imagefolder"

  setup_all do
    # Create test fixtures
    for label <- ["cat", "dog"] do
      dir = Path.join(@fixture_path, label)
      File.mkdir_p!(dir)

      for i <- 1..3 do
        # Create dummy image files
        path = Path.join(dir, "#{i}.jpg")
        File.write!(path, "fake image data #{label} #{i}")
      end
    end

    on_exit(fn ->
      File.rm_rf!(@fixture_path)
    end)

    :ok
  end

  describe "parse/2" do
    test "loads images from directory structure" do
      {:ok, items} = ImageFolder.parse(@fixture_path)

      assert length(items) == 6
      assert Enum.all?(items, &Map.has_key?(&1, "image"))
      assert Enum.all?(items, &Map.has_key?(&1, "label"))
    end

    test "extracts labels from directory names" do
      {:ok, items} = ImageFolder.parse(@fixture_path)

      labels = items |> Enum.map(& &1["label"]) |> Enum.uniq() |> Enum.sort()
      assert labels == ["cat", "dog"]
    end

    test "includes file paths" do
      {:ok, items} = ImageFolder.parse(@fixture_path)

      assert Enum.all?(items, fn item ->
        String.ends_with?(item["image"]["path"], ".jpg")
      end)
    end

    test "does not decode by default" do
      {:ok, items} = ImageFolder.parse(@fixture_path)

      assert Enum.all?(items, fn item ->
        is_nil(item["image"]["bytes"])
      end)
    end

    test "decodes when requested" do
      {:ok, items} = ImageFolder.parse(@fixture_path, decode: true)

      assert Enum.all?(items, fn item ->
        is_binary(item["image"]["bytes"])
      end)
    end

    test "respects extension filter" do
      {:ok, items} = ImageFolder.parse(@fixture_path, extensions: [".png"])
      assert items == []
    end

    test "returns error for non-existent path" do
      {:error, {:not_a_directory, _}} = ImageFolder.parse("/nonexistent/path")
    end

    test "handles empty directories" do
      empty_path = Path.join(@fixture_path, "empty_test")
      File.mkdir_p!(empty_path)

      {:ok, items} = ImageFolder.parse(empty_path)
      assert items == []

      File.rm_rf!(empty_path)
    end
  end

  describe "parse_stream/2" do
    test "returns a stream" do
      stream = ImageFolder.parse_stream(@fixture_path)
      assert is_function(stream, 2) or %Stream{} = stream

      items = Enum.to_list(stream)
      assert length(items) == 6
    end
  end
end
```

## Fixture Setup

Create test fixture directories:

```
test/fixtures/imagefolder/
├── cat/
│   ├── 1.jpg
│   ├── 2.jpg
│   └── 3.jpg
└── dog/
    ├── 1.jpg
    ├── 2.jpg
    └── 3.jpg
```

Note: Tests should create these programmatically in setup_all.

## Acceptance Criteria

1. `mix test test/dataset_manager/format/imagefolder_test.exs` passes
2. Works with common image extensions (.jpg, .png, etc.)
3. Labels are correctly extracted from directory names
4. Optional decoding works correctly
5. Stream version is actually lazy
6. `mix credo --strict` has no new issues
7. `mix dialyzer` has no new warnings
