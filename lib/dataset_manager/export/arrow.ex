defmodule HfDatasetsEx.Export.Arrow do
  @moduledoc """
  Export dataset to Apache Arrow IPC format.
  """

  alias HfDatasetsEx.Dataset

  @type options :: [
          compression: :lz4 | :zstd | nil
        ]

  @spec write(Dataset.t(), Path.t(), options()) :: :ok | {:error, term()}
  def write(%Dataset{items: items}, path, opts \\ []) do
    compression = Keyword.get(opts, :compression)

    with :ok <- ensure_parent_dir(path) do
      try do
        df = Explorer.DataFrame.new(items)

        ipc_opts =
          if compression do
            [compression: compression]
          else
            []
          end

        case Explorer.DataFrame.to_ipc(df, path, ipc_opts) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end
      rescue
        e -> {:error, e}
      end
    end
  end

  @doc """
  Write dataset to Arrow IPC stream format (for streaming).
  """
  @spec write_stream(Dataset.t(), Path.t(), options()) :: :ok | {:error, term()}
  def write_stream(%Dataset{items: items}, path, _opts \\ []) do
    with :ok <- ensure_parent_dir(path) do
      try do
        df = Explorer.DataFrame.new(items)

        case Explorer.DataFrame.to_ipc_stream(df, path) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end
      rescue
        e -> {:error, e}
      end
    end
  end

  defp ensure_parent_dir(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end
end
