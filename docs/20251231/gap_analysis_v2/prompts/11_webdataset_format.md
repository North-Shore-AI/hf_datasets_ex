# Implementation Prompt: Format.WebDataset

## Task

Implement WebDataset format parsing for loading datasets from tar archives where files are grouped by key prefix.

## Pre-Implementation Reading

Read these files to understand the existing codebase:

1. `lib/dataset_manager/format.ex` - Format registry and behaviour
2. `lib/dataset_manager/format/parquet.ex` - Complex format parser example
3. Erlang `:erl_tar` module documentation for tar handling

## Context

WebDataset is a format for efficient large-scale dataset storage using tar archives. Files in the archive are named with a common prefix (key) and different suffixes (extensions):

```
archive.tar
├── sample000001.jpg    # Image
├── sample000001.json   # Metadata
├── sample000001.txt    # Caption
├── sample000002.jpg
├── sample000002.json
├── sample000002.txt
└── ...
```

Each group of files with the same prefix becomes one dataset item:
```elixir
%{
  "__key__" => "sample000001",
  "jpg" => <<binary image data>>,
  "json" => %{"width" => 512, "height" => 512},
  "txt" => "A photo of a cat"
}
```

## Requirements

### 1. Format.WebDataset module

```elixir
defmodule HfDatasetsEx.Format.WebDataset do
  @moduledoc """
  Parse WebDataset tar archives into datasets.

  WebDataset is a format where samples are stored as groups of files
  in tar archives, with files grouped by a common key prefix.
  """

  @doc """
  Parse a tar archive into a list of samples.

  ## Options

    * `:decode` - Decode JSON files automatically (default: true)
    * `:extensions` - Only include these extensions (default: all)
    * `:max_samples` - Maximum number of samples to read

  ## Examples

      {:ok, items} = WebDataset.parse("data.tar")
      # [%{"__key__" => "000001", "jpg" => <<...>>, "txt" => "caption"}, ...]

  """
  @spec parse(Path.t(), keyword()) :: {:ok, [map()]} | {:error, term()}

  @doc """
  Stream samples from a tar archive for memory efficiency.
  """
  @spec stream(Path.t(), keyword()) :: Enumerable.t()
end
```

## File to Create

`lib/dataset_manager/format/webdataset.ex`

## Implementation

```elixir
defmodule HfDatasetsEx.Format.WebDataset do
  @moduledoc """
  Parse WebDataset tar archives into datasets.

  WebDataset is a format for efficient large-scale dataset storage where
  samples are grouped by key prefix in tar archives.

  ## Format Specification

  Files in the tar archive should be named:
  - `{key}.{extension}` (e.g., `sample001.jpg`, `sample001.json`)

  Files with the same key prefix are grouped into a single sample.

  ## Supported Content Types

  - `.json` - Parsed as JSON
  - `.txt`, `.text` - Loaded as text
  - `.jpg`, `.jpeg`, `.png`, `.webp` - Loaded as binary
  - `.mp3`, `.wav`, `.flac` - Loaded as binary
  - `.npy` - NumPy arrays (requires special handling)
  - Other - Loaded as raw binary

  ## Examples

      # Load all samples
      {:ok, items} = WebDataset.parse("dataset.tar")

      # Stream for large archives
      stream = WebDataset.stream("large_dataset.tar")
      Enum.each(stream, &process_sample/1)

  """

  @json_extensions ~w(.json .jsonl)
  @text_extensions ~w(.txt .text .caption .cls)

  @doc """
  Parse a tar archive into a list of samples.
  """
  @spec parse(Path.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def parse(path, opts \\ []) do
    max_samples = Keyword.get(opts, :max_samples)

    samples =
      path
      |> stream(opts)
      |> maybe_limit(max_samples)
      |> Enum.to_list()

    {:ok, samples}
  rescue
    e in [File.Error, ErlangError] ->
      {:error, {:tar_error, Exception.message(e)}}
  end

  @doc """
  Stream samples from a tar archive.
  """
  @spec stream(Path.t(), keyword()) :: Enumerable.t()
  def stream(path, opts \\ []) do
    decode_json = Keyword.get(opts, :decode, true)
    extensions = Keyword.get(opts, :extensions)

    path
    |> extract_tar_entries()
    |> group_by_key()
    |> Stream.map(&build_sample(&1, decode_json, extensions))
    |> Stream.reject(&is_nil/1)
  end

  @doc """
  Parse multiple tar archives (shards).
  """
  @spec parse_shards([Path.t()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def parse_shards(paths, opts \\ []) do
    items =
      paths
      |> Enum.flat_map(fn path ->
        case parse(path, opts) do
          {:ok, items} -> items
          {:error, _} -> []
        end
      end)

    {:ok, items}
  end

  @doc """
  Stream from multiple tar archives (shards).
  """
  @spec stream_shards([Path.t()], keyword()) :: Enumerable.t()
  def stream_shards(paths, opts \\ []) do
    paths
    |> Stream.flat_map(&stream(&1, opts))
  end

  # Private implementation

  defp extract_tar_entries(path) do
    Stream.resource(
      fn -> open_tar(path) end,
      &read_next_entry/1,
      &close_tar/1
    )
  end

  defp open_tar(path) do
    {:ok, handle} = :erl_tar.open(path, [:read, :compressed])
    handle
  end

  defp read_next_entry(handle) do
    case :erl_tar.extract(handle, [:memory, :next]) do
      {:ok, []} ->
        {:halt, handle}

      {:ok, [{name, content}]} ->
        {[{to_string(name), content}], handle}

      :eof ->
        {:halt, handle}

      {:error, reason} ->
        raise "Tar extraction error: #{inspect(reason)}"
    end
  end

  defp close_tar(handle) do
    :erl_tar.close(handle)
  end

  defp group_by_key(entries_stream) do
    entries_stream
    |> Stream.transform(
      %{},  # accumulator: key -> list of {ext, content}
      fn {name, content}, acc ->
        {key, ext} = split_key_ext(name)

        if key do
          updated = Map.update(acc, key, [{ext, content}], &[{ext, content} | &1])
          {[], updated}
        else
          {[], acc}
        end
      end,
      fn acc ->
        # Emit all accumulated groups at the end
        samples = Enum.map(acc, fn {key, files} -> {key, Enum.reverse(files)} end)
        {samples, acc}
      end
    )
  end

  defp split_key_ext(name) do
    # Handle paths like "subdir/sample001.jpg"
    basename = Path.basename(name)
    ext = Path.extname(basename)
    key = Path.rootname(basename)

    if String.length(key) > 0 and String.length(ext) > 0 do
      # Remove the leading dot from extension
      {key, String.slice(ext, 1..-1//1)}
    else
      {nil, nil}
    end
  end

  defp build_sample({key, files}, decode_json, extensions) do
    sample = %{"__key__" => key}

    files
    |> Enum.filter(fn {ext, _} ->
      is_nil(extensions) or ext in extensions
    end)
    |> Enum.reduce(sample, fn {ext, content}, acc ->
      value = decode_content(ext, content, decode_json)
      Map.put(acc, ext, value)
    end)
  end

  defp decode_content(ext, content, decode_json) do
    cond do
      ext in @json_extensions and decode_json ->
        case Jason.decode(content) do
          {:ok, parsed} -> parsed
          {:error, _} -> content
        end

      ext in @text_extensions ->
        String.trim(content)

      true ->
        content
    end
  end

  defp maybe_limit(stream, nil), do: stream
  defp maybe_limit(stream, n), do: Stream.take(stream, n)
end
```

## Alternative Implementation (Simpler)

If streaming is not required, a simpler implementation:

```elixir
defmodule HfDatasetsEx.Format.WebDataset do
  @json_extensions ~w(.json)
  @text_extensions ~w(.txt .text .caption)

  def parse(path, opts \\ []) do
    decode_json = Keyword.get(opts, :decode, true)

    case :erl_tar.extract(path, [:memory, :compressed]) do
      {:ok, files} ->
        items =
          files
          |> Enum.map(fn {name, content} -> {to_string(name), content} end)
          |> group_by_key()
          |> Enum.map(&build_sample(&1, decode_json))
          |> Enum.sort_by(& &1["__key__"])

        {:ok, items}

      {:error, reason} ->
        {:error, {:tar_error, reason}}
    end
  end

  defp group_by_key(files) do
    files
    |> Enum.group_by(
      fn {name, _} -> Path.rootname(Path.basename(name)) end,
      fn {name, content} -> {Path.extname(name) |> String.slice(1..-1//1), content} end
    )
  end

  defp build_sample({key, file_pairs}, decode_json) do
    base = %{"__key__" => key}

    Enum.reduce(file_pairs, base, fn {ext, content}, acc ->
      value = decode_content(ext, content, decode_json)
      Map.put(acc, ext, value)
    end)
  end

  defp decode_content(ext, content, true) when ext in @json_extensions do
    case Jason.decode(content) do
      {:ok, parsed} -> parsed
      {:error, _} -> content
    end
  end

  defp decode_content(ext, content, _) when ext in @text_extensions do
    String.trim(content)
  end

  defp decode_content(_ext, content, _), do: content
end
```

## Tests

Create `test/dataset_manager/format/webdataset_test.exs`:

```elixir
defmodule HfDatasetsEx.Format.WebDatasetTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Format.WebDataset

  @fixtures_path "test/fixtures/webdataset"
  @tar_path Path.join(@fixtures_path, "test.tar")

  setup do
    File.rm_rf!(@fixtures_path)
    File.mkdir_p!(@fixtures_path)

    # Create a test tar archive
    create_test_tar()

    on_exit(fn ->
      File.rm_rf!(@fixtures_path)
    end)

    :ok
  end

  defp create_test_tar do
    # Create sample files
    files = [
      {"sample001.txt", "Hello world"},
      {"sample001.json", ~s({"label": "cat", "score": 0.95})},
      {"sample002.txt", "Goodbye world"},
      {"sample002.json", ~s({"label": "dog", "score": 0.87})}
    ]

    # Write temporary files
    tmp_dir = Path.join(@fixtures_path, "tmp")
    File.mkdir_p!(tmp_dir)

    file_paths =
      Enum.map(files, fn {name, content} ->
        path = Path.join(tmp_dir, name)
        File.write!(path, content)
        String.to_charlist(path)
      end)

    # Create tar archive
    :erl_tar.create(String.to_charlist(@tar_path), file_paths, [:compressed])

    # Clean up temp files
    File.rm_rf!(tmp_dir)
  end

  describe "parse/2" do
    test "parses tar archive into samples" do
      {:ok, items} = WebDataset.parse(@tar_path)

      assert length(items) == 2

      sample1 = Enum.find(items, & &1["__key__"] == "sample001")
      assert sample1["txt"] == "Hello world"
      assert sample1["json"]["label"] == "cat"
      assert sample1["json"]["score"] == 0.95
    end

    test "groups files by key" do
      {:ok, items} = WebDataset.parse(@tar_path)

      Enum.each(items, fn item ->
        assert Map.has_key?(item, "__key__")
        assert Map.has_key?(item, "txt")
        assert Map.has_key?(item, "json")
      end)
    end

    test "decodes JSON by default" do
      {:ok, [item | _]} = WebDataset.parse(@tar_path)

      assert is_map(item["json"])
    end

    test "skips JSON decoding when decode: false" do
      {:ok, [item | _]} = WebDataset.parse(@tar_path, decode: false)

      assert is_binary(item["json"])
    end

    test "handles missing file" do
      {:error, {:tar_error, _}} = WebDataset.parse("nonexistent.tar")
    end
  end

  describe "stream/2" do
    test "returns a stream of samples" do
      stream = WebDataset.stream(@tar_path)

      items = Enum.to_list(stream)
      assert length(items) == 2
    end

    test "stream is lazy" do
      stream = WebDataset.stream(@tar_path)

      [first] = Enum.take(stream, 1)
      assert Map.has_key?(first, "__key__")
    end
  end

  describe "with binary content" do
    test "loads binary files as-is" do
      # Create tar with binary content
      binary_tar = Path.join(@fixtures_path, "binary.tar")

      tmp_dir = Path.join(@fixtures_path, "tmp2")
      File.mkdir_p!(tmp_dir)

      img_path = Path.join(tmp_dir, "sample.jpg")
      File.write!(img_path, <<0xFF, 0xD8, 0xFF, 0xE0>>)  # JPEG magic bytes

      :erl_tar.create(
        String.to_charlist(binary_tar),
        [String.to_charlist(img_path)],
        [:compressed]
      )

      File.rm_rf!(tmp_dir)

      {:ok, [item]} = WebDataset.parse(binary_tar)
      assert item["jpg"] == <<0xFF, 0xD8, 0xFF, 0xE0>>
    end
  end
end
```

## Edge Cases

1. **Empty archive**: Return empty list
2. **Corrupted archive**: Return error
3. **Files without extensions**: Skip or use filename as key
4. **Nested directories**: Flatten or preserve structure
5. **Large archives**: Use streaming
6. **Compressed archives**: Support .tar.gz, .tar.bz2
7. **Invalid JSON**: Keep as string instead of failing

## Future Enhancements

1. **Shard patterns**: Support glob patterns like `data-{00000..00099}.tar`
2. **Shuffle shards**: Random shard ordering
3. **Resume**: Track position for checkpoint/resume
4. **Write support**: Create WebDataset archives
5. **Remote archives**: Stream from URLs
6. **Parallel extraction**: Multi-threaded tar reading

## Acceptance Criteria

1. All tests pass
2. Handles common tar variations
3. Memory efficient for large archives
4. Documentation with examples
5. Error handling for corrupted archives

## Python Parity Notes

Python WebDataset features we're implementing:
- Key-based grouping ✓
- JSON decoding ✓
- Streaming ✓
- Multiple shards ✓

Python features for future:
- URL streaming
- Shuffle buffers
- Batching
- Decoders pipeline
