defmodule HfDatasetsEx.Source.Local do
  @moduledoc """
  Local filesystem source for datasets.

  Supports loading from:
  - Single files (jsonl, json, csv, parquet)
  - Directories containing data files

  ## Examples

      # Load from single file
      {:ok, files} = Local.list_files("./data/train.jsonl", [])

      # Load from directory
      {:ok, files} = Local.list_files("./data/my_dataset/", [])

  """

  @behaviour HfDatasetsEx.Source

  alias HfDatasetsEx.Source

  @impl true
  def list_files(path, _opts) do
    cond do
      not File.exists?(path) ->
        {:error, :not_found}

      File.dir?(path) ->
        files =
          Path.wildcard(Path.join(path, "**/*"))
          |> Enum.reject(&File.dir?/1)
          |> Enum.map(&file_info/1)

        {:ok, files}

      true ->
        {:ok, [file_info(path)]}
    end
  end

  @impl true
  def download(path, _file_path, _opts) do
    # Local files don't need download - just return the path
    if File.exists?(path) do
      {:ok, path}
    else
      {:error, :not_found}
    end
  end

  @impl true
  def stream(path, _file_path, _opts) do
    if File.exists?(path) do
      {:ok, File.stream!(path, :line)}
    else
      {:error, :not_found}
    end
  end

  @impl true
  def exists?(path, _opts) do
    File.exists?(path)
  end

  defp file_info(path) do
    stat = File.stat!(path)

    %{
      path: path,
      size: stat.size,
      format: Source.detect_format(path)
    }
  end
end
