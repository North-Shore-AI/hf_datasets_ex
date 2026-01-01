# Implementation Prompt: Format.AudioFolder

## Task

Implement folder-based audio dataset loading where subdirectories represent class labels.

## Pre-Implementation Reading

Read these files to understand the existing codebase:

1. `lib/dataset_manager/format/imagefolder.ex` - ImageFolder implementation to follow as pattern
2. `lib/dataset_manager/features/audio.ex` - Audio feature type
3. `lib/dataset_manager/format.ex` - Format registry
4. `test/dataset_manager/format/imagefolder_test.exs` - Test patterns

## Context

Similar to ImageFolder, AudioFolder is a common pattern for audio classification datasets:
```
data/
├── speech/
│   ├── sample1.wav
│   └── sample2.mp3
├── music/
│   ├── track1.wav
│   └── track2.flac
└── noise/
    ├── background1.wav
    └── background2.ogg
```

## Requirements

### 1. Format.AudioFolder module

```elixir
defmodule HfDatasetsEx.Format.AudioFolder do
  @moduledoc """
  Load audio datasets from directory structure where subdirectories are labels.

  ## Supported Formats

    * WAV (.wav)
    * MP3 (.mp3)
    * FLAC (.flac)
    * OGG (.ogg)
    * M4A (.m4a)

  ## Examples

      {:ok, items} = AudioFolder.parse("./audio_data")
      # Returns:
      # [
      #   %{"audio" => %{path: ".../speech/sample1.wav", bytes: nil}, "label" => "speech"},
      #   %{"audio" => %{path: ".../music/track1.wav", bytes: nil}, "label" => "music"},
      #   ...
      # ]

  """
end
```

## File to Create

`lib/dataset_manager/format/audiofolder.ex`

## Implementation

```elixir
defmodule HfDatasetsEx.Format.AudioFolder do
  @moduledoc """
  Load audio datasets from directory structure where subdirectories are labels.
  """

  @audio_extensions ~w(.wav .mp3 .flac .ogg .m4a .aac .wma)

  @doc """
  Parse a directory structure into audio dataset items.

  ## Options

    * `:decode` - Load audio bytes into memory (default: false)
    * `:extensions` - Custom list of extensions to include
    * `:recursive` - Search subdirectories recursively (default: false)
    * `:sample_rate` - Expected sample rate for validation

  ## Examples

      # Just paths
      {:ok, items} = AudioFolder.parse("./data")

      # With audio bytes loaded
      {:ok, items} = AudioFolder.parse("./data", decode: true)

      # Custom extensions
      {:ok, items} = AudioFolder.parse("./data", extensions: [".wav", ".flac"])

  """
  @spec parse(Path.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def parse(path, opts \\ []) do
    decode = Keyword.get(opts, :decode, false)
    extensions = Keyword.get(opts, :extensions, @audio_extensions)
    recursive = Keyword.get(opts, :recursive, false)

    pattern = if recursive do
      Path.join(path, "**/*")
    else
      Path.join(path, "*/*")
    end

    items =
      pattern
      |> Path.wildcard()
      |> Enum.filter(&audio_file?(&1, extensions))
      |> Enum.map(&to_item(&1, path, decode))
      |> Enum.sort_by(& &1["label"])

    {:ok, items}
  rescue
    e in File.Error ->
      {:error, {:file_error, e.reason}}
  end

  @doc """
  Parse and return as a stream for large datasets.
  """
  @spec stream(Path.t(), keyword()) :: Enumerable.t()
  def stream(path, opts \\ []) do
    decode = Keyword.get(opts, :decode, false)
    extensions = Keyword.get(opts, :extensions, @audio_extensions)

    path
    |> Path.join("*/*")
    |> Path.wildcard()
    |> Stream.filter(&audio_file?(&1, extensions))
    |> Stream.map(&to_item(&1, path, decode))
  end

  @doc """
  Get all unique labels (subdirectory names) in the dataset.
  """
  @spec get_labels(Path.t()) :: [String.t()]
  def get_labels(path) do
    path
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(&Path.basename/1)
    |> Enum.sort()
  end

  @doc """
  Count files per label.
  """
  @spec count_per_label(Path.t(), keyword()) :: %{String.t() => non_neg_integer()}
  def count_per_label(path, opts \\ []) do
    extensions = Keyword.get(opts, :extensions, @audio_extensions)

    path
    |> get_labels()
    |> Map.new(fn label ->
      count =
        path
        |> Path.join(label)
        |> Path.join("*")
        |> Path.wildcard()
        |> Enum.count(&audio_file?(&1, extensions))

      {label, count}
    end)
  end

  # Private helpers

  defp audio_file?(file_path, extensions) do
    ext = Path.extname(file_path) |> String.downcase()
    File.regular?(file_path) && ext in extensions
  end

  defp to_item(file_path, base_path, decode) do
    label = extract_label(file_path, base_path)

    audio = %{
      "path" => file_path,
      "bytes" => if(decode, do: File.read!(file_path), else: nil)
    }

    %{"audio" => audio, "label" => label}
  end

  defp extract_label(file_path, base_path) do
    # Get the immediate parent directory name as label
    file_path
    |> Path.relative_to(base_path)
    |> Path.dirname()
    |> Path.basename()
  end
end
```

## Register Format

Update `lib/dataset_manager/format.ex`:

```elixir
@folder_formats %{
  "imagefolder" => HfDatasetsEx.Format.ImageFolder,
  "audiofolder" => HfDatasetsEx.Format.AudioFolder
}
```

## Tests

Create `test/dataset_manager/format/audiofolder_test.exs`:

```elixir
defmodule HfDatasetsEx.Format.AudioFolderTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Format.AudioFolder

  @fixtures_path "test/fixtures/audiofolder"

  setup do
    # Create test directory structure
    File.rm_rf!(@fixtures_path)
    File.mkdir_p!(Path.join(@fixtures_path, "speech"))
    File.mkdir_p!(Path.join(@fixtures_path, "music"))
    File.mkdir_p!(Path.join(@fixtures_path, "empty_class"))

    # Create dummy audio files
    File.write!(Path.join([@fixtures_path, "speech", "hello.wav"]), "RIFF...")
    File.write!(Path.join([@fixtures_path, "speech", "goodbye.mp3"]), "ID3...")
    File.write!(Path.join([@fixtures_path, "music", "song.wav"]), "RIFF...")
    File.write!(Path.join([@fixtures_path, "music", "track.flac"]), "fLaC...")

    on_exit(fn ->
      File.rm_rf!(@fixtures_path)
    end)

    :ok
  end

  describe "parse/2" do
    test "loads audio files with labels from subdirectories" do
      {:ok, items} = AudioFolder.parse(@fixtures_path)

      assert length(items) == 4

      labels = Enum.map(items, & &1["label"]) |> Enum.uniq() |> Enum.sort()
      assert labels == ["music", "speech"]
    end

    test "returns audio paths without bytes by default" do
      {:ok, items} = AudioFolder.parse(@fixtures_path)

      item = hd(items)
      assert is_map(item["audio"])
      assert is_binary(item["audio"]["path"])
      assert is_nil(item["audio"]["bytes"])
    end

    test "loads audio bytes when decode: true" do
      {:ok, items} = AudioFolder.parse(@fixtures_path, decode: true)

      item = hd(items)
      assert is_binary(item["audio"]["bytes"])
    end

    test "respects custom extensions" do
      {:ok, items} = AudioFolder.parse(@fixtures_path, extensions: [".wav"])

      assert length(items) == 2
      assert Enum.all?(items, fn item ->
        String.ends_with?(item["audio"]["path"], ".wav")
      end)
    end

    test "handles empty directories" do
      {:ok, items} = AudioFolder.parse(@fixtures_path)

      labels = Enum.map(items, & &1["label"]) |> Enum.uniq()
      refute "empty_class" in labels
    end

    test "handles non-existent path" do
      {:error, {:file_error, :enoent}} = AudioFolder.parse("/nonexistent/path")
    end

    test "ignores non-audio files" do
      File.write!(Path.join([@fixtures_path, "speech", "readme.txt"]), "text")

      {:ok, items} = AudioFolder.parse(@fixtures_path)

      paths = Enum.map(items, & &1["audio"]["path"])
      refute Enum.any?(paths, &String.ends_with?(&1, ".txt"))
    end
  end

  describe "get_labels/1" do
    test "returns sorted list of labels" do
      labels = AudioFolder.get_labels(@fixtures_path)

      assert labels == ["empty_class", "music", "speech"]
    end
  end

  describe "count_per_label/2" do
    test "counts files per label" do
      counts = AudioFolder.count_per_label(@fixtures_path)

      assert counts["speech"] == 2
      assert counts["music"] == 2
      assert counts["empty_class"] == 0
    end
  end

  describe "stream/2" do
    test "returns a stream of items" do
      stream = AudioFolder.stream(@fixtures_path)

      items = Enum.to_list(stream)
      assert length(items) == 4
    end

    test "stream is lazy" do
      # Should not read files until consumed
      stream = AudioFolder.stream(@fixtures_path, decode: true)

      # Take only first item
      [item] = Enum.take(stream, 1)
      assert is_binary(item["audio"]["bytes"])
    end
  end
end
```

## Integration with Dataset

Add convenience function:

```elixir
defmodule HfDatasetsEx.Dataset do
  @doc """
  Load a dataset from an AudioFolder directory structure.

  ## Examples

      {:ok, dataset} = Dataset.from_audiofolder("./audio_data")

  """
  @spec from_audiofolder(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_audiofolder(path, opts \\ []) do
    case Format.AudioFolder.parse(path, opts) do
      {:ok, items} ->
        # Set up features
        labels = Format.AudioFolder.get_labels(path)
        features = Features.new(%{
          "audio" => Features.Audio.new(),
          "label" => Features.ClassLabel.new(names: labels)
        })

        {:ok, from_list(items, features: features)}

      error ->
        error
    end
  end
end
```

## Edge Cases

1. **Hidden files/directories**: Ignore `.` prefixed items
2. **Symlinks**: Follow or ignore based on option
3. **Nested subdirectories**: Handle with `recursive: true`
4. **Special characters**: Handle unicode in filenames
5. **Large files**: Stream to avoid memory issues
6. **Corrupted files**: Option to skip or error

## Future Enhancements

1. **Audio metadata**: Extract duration, sample rate, channels
2. **Audio decoding**: Decode to Nx tensor using audio library
3. **Resampling**: Resample to consistent sample rate
4. **Splits file**: Support train/test splits via text file
5. **Metadata file**: Support metadata.csv for additional columns

## Acceptance Criteria

1. `mix test test/dataset_manager/format/audiofolder_test.exs` passes
2. Works with common audio formats
3. Handles edge cases gracefully
4. Documentation with examples
5. Integrates with Dataset.from_audiofolder/2

## Python Parity Notes

Python AudioFolder features:
- Auto-generates ClassLabel from folder names (we do this)
- Decodes audio to numpy arrays (we return bytes/paths)
- Supports splits via config (future enhancement)
- Metadata file support (future enhancement)
