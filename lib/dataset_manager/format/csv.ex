defmodule HfDatasetsEx.Format.CSV do
  @moduledoc """
  CSV format parser.

  Parses CSV files with headers into list of maps.

  ## Example

      {:ok, items} = CSV.parse("data.csv")
      # => [%{"id" => "1", "text" => "hello"}, ...]

  Note: All values are returned as strings.
  """

  @behaviour HfDatasetsEx.Format

  @impl true
  @spec parse(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def parse(path, opts \\ []) do
    delimiter = Keyword.get(opts, :delimiter, ",") |> to_string()
    headers? = Keyword.get(opts, :headers, true)

    lines =
      path
      |> File.stream!(:line)
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Enum.to_list()

    case lines do
      [] ->
        {:ok, []}

      [header_line | data_lines] when headers? ->
        headers = split_line(header_line, delimiter)

        items =
          data_lines
          |> Enum.map(fn line ->
            values = split_line(line, delimiter)
            Enum.zip(headers, values) |> Map.new()
          end)

        {:ok, items}

      [first_line | rest_lines] ->
        first_values = split_line(first_line, delimiter)
        headers = Enum.map(1..length(first_values), &"column_#{&1}")
        rows = [first_line | rest_lines]

        items =
          rows
          |> Enum.map(fn line ->
            values = split_line(line, delimiter)
            Enum.zip(headers, values) |> Map.new()
          end)

        {:ok, items}
    end
  rescue
    e -> {:error, {:parse_error, e}}
  end

  def parse_stream(path_or_stream), do: parse_stream(path_or_stream, [])

  @impl true
  def parse_stream(path, opts) when is_binary(path) do
    path
    |> File.stream!(:line)
    |> parse_stream(opts)
  end

  def parse_stream(stream, opts) do
    delimiter = Keyword.get(opts, :delimiter, ",") |> to_string()
    headers? = Keyword.get(opts, :headers, true)

    stream
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.transform({:start, nil}, fn
      line, {:start, nil} when headers? ->
        headers = split_line(line, delimiter)
        {[], {:headers, headers}}

      line, {:start, nil} ->
        values = split_line(line, delimiter)
        headers = Enum.map(1..length(values), &"column_#{&1}")
        item = Enum.zip(headers, values) |> Map.new()
        {[item], {:headers, headers}}

      line, {:headers, headers} ->
        values = split_line(line, delimiter)
        item = Enum.zip(headers, values) |> Map.new()
        {[item], {:headers, headers}}
    end)
  end

  @impl true
  def handles?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext in [".csv", ".tsv"]
  end

  defp split_line(line, delimiter) do
    line
    |> String.split(delimiter)
    |> Enum.map(&String.trim/1)
  end
end
