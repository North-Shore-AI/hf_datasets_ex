defmodule HfDatasetsEx.Format.Arrow do
  @moduledoc """
  Parser for Apache Arrow IPC format files.

  Uses Explorer's Arrow support.
  """

  @behaviour HfDatasetsEx.Format

  @type options :: [
          columns: [String.t()] | nil,
          batch_size: pos_integer()
        ]

  @impl true
  @spec parse(Path.t(), options()) :: {:ok, [map()]} | {:error, term()}
  def parse(path, opts \\ []) do
    columns = Keyword.get(opts, :columns)

    try do
      df = Explorer.DataFrame.from_ipc!(path)

      df =
        if columns do
          Explorer.DataFrame.select(df, columns)
        else
          df
        end

      items = Explorer.DataFrame.to_rows(df)
      {:ok, items}
    rescue
      e -> {:error, e}
    end
  end

  def parse_stream(path_or_stream), do: parse_stream(path_or_stream, [])

  @impl true
  @spec parse_stream(Path.t(), options()) :: Enumerable.t()
  def parse_stream(path, opts) when is_binary(path) do
    batch_size = Keyword.get(opts, :batch_size, 10_000)

    # Arrow IPC doesn't support true streaming in Explorer
    # Load and chunk
    {:ok, items} = parse(path, opts)

    Stream.chunk_every(items, batch_size)
    |> Stream.flat_map(& &1)
  end

  def parse_stream(_stream, _opts) do
    raise "Arrow format does not support streaming from enumerables. Use parse/2 instead."
  end

  @impl true
  def handles?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext in [".arrow", ".ipc"]
  end

  @doc """
  Check if file is a valid Arrow IPC file.
  """
  @spec valid?(Path.t()) :: boolean()
  def valid?(path) do
    case File.read(path) do
      {:ok, data} ->
        has_prefix = byte_size(data) >= 6 and :binary.part(data, 0, 6) == "ARROW1"

        has_suffix =
          byte_size(data) >= 8 and
            :binary.part(data, byte_size(data) - 8, 8) == <<255, 255, 255, 255, 0, 0, 0, 0>>

        has_prefix or has_suffix

      _ ->
        false
    end
  end
end
