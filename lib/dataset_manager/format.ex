defmodule HfDatasetsEx.Format do
  @moduledoc """
  Format detection and parser registry.
  """

  @doc "Parse file contents into list of maps"
  @callback parse(Path.t(), keyword()) :: {:ok, [map()]} | {:error, term()}

  @doc "Parse streaming contents lazily"
  @callback parse_stream(Path.t(), keyword()) :: Enumerable.t()

  @doc "Detect if this format can handle the file"
  @callback handles?(Path.t()) :: boolean()

  @optional_callbacks [parse_stream: 2]

  @extension_map %{
    ".jsonl" => HfDatasetsEx.Format.JSONL,
    ".jsonlines" => HfDatasetsEx.Format.JSONL,
    ".ndjson" => HfDatasetsEx.Format.JSONL,
    ".json" => HfDatasetsEx.Format.JSON,
    ".csv" => HfDatasetsEx.Format.CSV,
    ".tsv" => {HfDatasetsEx.Format.CSV, [delimiter: "\t"]},
    ".parquet" => HfDatasetsEx.Format.Parquet,
    ".txt" => HfDatasetsEx.Format.Text,
    ".text" => HfDatasetsEx.Format.Text,
    ".arrow" => HfDatasetsEx.Format.Arrow,
    ".ipc" => HfDatasetsEx.Format.Arrow
  }

  @doc """
  Detect format from file extension.
  """
  @spec detect(Path.t()) :: {:ok, module(), keyword()} | {:error, :unknown_format}
  def detect(path) do
    ext = Path.extname(path) |> String.downcase()

    case Map.get(@extension_map, ext) do
      nil -> {:error, :unknown_format}
      {module, opts} -> {:ok, module, opts}
      module -> {:ok, module, []}
    end
  end

  @doc """
  Get the parser module for a format.
  """
  @spec parser_for(atom()) :: module() | {module(), keyword()} | nil
  def parser_for(:jsonl), do: HfDatasetsEx.Format.JSONL
  def parser_for(:json), do: HfDatasetsEx.Format.JSON
  def parser_for(:csv), do: HfDatasetsEx.Format.CSV
  def parser_for(:tsv), do: {HfDatasetsEx.Format.CSV, [delimiter: "\t"]}
  def parser_for(:parquet), do: HfDatasetsEx.Format.Parquet
  def parser_for(:text), do: HfDatasetsEx.Format.Text
  def parser_for(:arrow), do: HfDatasetsEx.Format.Arrow
  def parser_for(_), do: nil

  @doc """
  Parse file using detected format.
  """
  @spec parse(Path.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def parse(path, opts \\ []) do
    case detect(path) do
      {:ok, module, default_opts} ->
        module.parse(path, Keyword.merge(default_opts, opts))

      {:error, reason} ->
        {:error, reason}
    end
  end
end
