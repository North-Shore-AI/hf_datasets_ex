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
  def parse(path) do
    lines =
      path
      |> File.stream!(:line)
      |> Enum.to_list()

    case lines do
      [] ->
        {:ok, []}

      [header_line | data_lines] ->
        headers =
          header_line
          |> String.trim()
          |> String.split(",")
          |> Enum.map(&String.trim/1)

        items =
          data_lines
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(fn line ->
            values = String.split(line, ",") |> Enum.map(&String.trim/1)
            Enum.zip(headers, values) |> Map.new()
          end)

        {:ok, items}
    end
  rescue
    e -> {:error, {:parse_error, e}}
  end

  @impl true
  def parse_stream(stream) do
    # Get first line as headers, then map rest
    stream
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.transform(nil, fn
      line, nil ->
        # First line is headers
        headers = String.split(line, ",") |> Enum.map(&String.trim/1)
        {[], headers}

      line, headers ->
        values = String.split(line, ",") |> Enum.map(&String.trim/1)
        item = Enum.zip(headers, values) |> Map.new()
        {[item], headers}
    end)
  end

  @impl true
  def handles?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext == ".csv"
  end
end
