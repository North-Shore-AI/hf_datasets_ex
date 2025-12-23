defmodule HfDatasetsEx.Format do
  @moduledoc """
  Behaviour for data format parsers.

  Formats are responsible for parsing raw data files into Elixir maps.
  They are source-agnostic and work with local file paths.

  ## Implementations

  - `HfDatasetsEx.Format.JSONL` - JSON Lines format
  - `HfDatasetsEx.Format.JSON` - JSON format
  - `HfDatasetsEx.Format.CSV` - CSV format
  - `HfDatasetsEx.Format.Parquet` - Parquet format (via Explorer)

  ## Example

      # Parse a JSONL file
      {:ok, items} = Format.JSONL.parse("data.jsonl")

      # Stream parse for large files
      stream = File.stream!("data.jsonl")
      items = Format.JSONL.parse_stream(stream) |> Enum.take(100)

  """

  @doc "Parse file contents into list of maps"
  @callback parse(path :: String.t()) :: {:ok, [map()]} | {:error, term()}

  @doc "Parse streaming contents lazily"
  @callback parse_stream(stream :: Enumerable.t()) :: Enumerable.t()

  @doc "Detect if this format can handle the file"
  @callback handles?(path :: String.t()) :: boolean()

  @doc """
  Detect format from file extension.
  """
  @spec detect(String.t()) :: atom()
  def detect(path) when is_binary(path) do
    case Path.extname(path) |> String.downcase() do
      ".parquet" -> :parquet
      ".jsonl" -> :jsonl
      ".jsonlines" -> :jsonl
      ".json" -> :json
      ".csv" -> :csv
      ".txt" -> :text
      ".arrow" -> :arrow
      _ -> :unknown
    end
  end

  @doc """
  Get the parser module for a format.
  """
  @spec parser_for(atom()) :: module() | nil
  def parser_for(:jsonl), do: HfDatasetsEx.Format.JSONL
  def parser_for(:json), do: HfDatasetsEx.Format.JSON
  def parser_for(:csv), do: HfDatasetsEx.Format.CSV
  def parser_for(:parquet), do: HfDatasetsEx.Format.Parquet
  def parser_for(_), do: nil

  @doc """
  Parse a file using the appropriate format parser.
  """
  @spec parse(String.t()) :: {:ok, [map()]} | {:error, term()}
  def parse(path) do
    format = detect(path)
    do_parse(path, format)
  end

  defp do_parse(path, :jsonl), do: HfDatasetsEx.Format.JSONL.parse(path)
  defp do_parse(path, :json), do: HfDatasetsEx.Format.JSON.parse(path)
  defp do_parse(path, :csv), do: HfDatasetsEx.Format.CSV.parse(path)
  defp do_parse(path, :parquet), do: HfDatasetsEx.Format.Parquet.parse(path)
  defp do_parse(_path, format), do: {:error, {:unknown_format, format}}
end
