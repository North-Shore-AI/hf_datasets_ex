defmodule HfDatasetsEx.Format.Parquet do
  @moduledoc """
  Parquet format parser using Explorer.

  Parses Apache Parquet files into list of maps.

  ## Example

      {:ok, items} = Parquet.parse("data.parquet")
      # => [%{"id" => 1, "text" => "hello"}, ...]

  ## Dependencies

  Requires `explorer` package for Parquet support.
  """

  @behaviour HfDatasetsEx.Format

  @impl true
  def parse(path) do
    backend = parquet_backend()

    case backend.from_parquet(path, rechunk: true) do
      {:ok, df} ->
        items = backend.to_rows(df)
        {:ok, items}

      {:error, reason} ->
        {:error, {:parquet_error, reason}}
    end
  rescue
    e -> {:error, {:parse_error, e}}
  end

  @impl true
  def parse_stream(_stream) do
    # Parquet doesn't support true streaming
    # Would need chunked reads via Explorer
    raise "Parquet format does not support streaming. Use parse/1 instead."
  end

  @doc """
  Stream Parquet rows in batches.

  Note: Explorer reads the full file up-front; this only batches the iteration.
  """
  @spec stream_rows(String.t(), keyword()) :: Enumerable.t()
  def stream_rows(path, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 1000)
    backend = parquet_backend()

    Stream.resource(
      fn ->
        case backend.from_parquet(path, rechunk: true) do
          {:ok, df} ->
            %{
              dataframe: df,
              total_rows: backend.n_rows(df),
              offset: 0,
              batch_size: batch_size
            }

          {:error, reason} ->
            {:error, reason}
        end
      end,
      fn
        {:error, _reason} = state ->
          {:halt, state}

        %{offset: offset, total_rows: total} = state when offset >= total ->
          {:halt, state}

        %{dataframe: df, offset: offset, batch_size: size} = state ->
          batch_df = backend.slice(df, offset, size)
          rows = backend.to_rows(batch_df)
          {rows, %{state | offset: offset + size}}
      end,
      fn _ -> :ok end
    )
  end

  @impl true
  def handles?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext == ".parquet"
  end

  defp parquet_backend do
    Application.get_env(:hf_datasets_ex, :parquet_backend, Explorer.DataFrame)
  end
end
