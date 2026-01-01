defmodule HfDatasetsEx.Format.JSONL do
  @moduledoc """
  JSON Lines format parser.

  Parses files where each line is a valid JSON object.

  ## Example

      {:ok, items} = JSONL.parse("data.jsonl")
      # => [%{"id" => 1, ...}, %{"id" => 2, ...}]

  """

  @behaviour HfDatasetsEx.Format

  @impl true
  def parse(path, _opts \\ []) do
    items =
      path
      |> File.stream!(:line)
      |> parse_stream()
      |> Enum.to_list()

    {:ok, items}
  rescue
    e -> {:error, {:parse_error, e}}
  end

  def parse_stream(path_or_stream), do: parse_stream(path_or_stream, [])

  @impl true
  def parse_stream(path, _opts) when is_binary(path) do
    path
    |> File.stream!(:line)
    |> parse_stream()
  end

  def parse_stream(stream, _opts) do
    stream
    |> line_stream()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.map(&Jason.decode!/1)
  end

  @impl true
  def handles?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext in [".jsonl", ".jsonlines", ".ndjson"]
  end

  defp line_stream(stream) do
    Stream.transform(
      stream,
      fn -> "" end,
      fn chunk, buffer ->
        data = buffer <> chunk
        parts = String.split(data, "\n", trim: false)

        case parts do
          [] ->
            {[], buffer}

          _ ->
            {Enum.drop(parts, -1), List.last(parts)}
        end
      end,
      fn buffer ->
        if buffer == "", do: [], else: [buffer]
      end
    )
  end
end
