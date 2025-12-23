defmodule HfDatasetsEx.Source.HuggingFace do
  @moduledoc """
  HuggingFace Hub source for datasets.

  Wraps `hf_hub_ex` for downloading datasets from the HuggingFace Hub.

  ## Examples

      # List files in a dataset
      {:ok, files} = HuggingFace.list_files("openai/gsm8k", split: "test", config: "main")

      # Download a specific file
      {:ok, path} = HuggingFace.download("openai/gsm8k", "test.parquet", split: "test")

      # Check if dataset exists
      HuggingFace.exists?("openai/gsm8k", [])

  """

  @behaviour HfDatasetsEx.Source

  alias HfDatasetsEx.Source

  @impl true
  def list_files(repo_id, opts) do
    config = Keyword.get(opts, :config)
    split = Keyword.get(opts, :split)
    token = Keyword.get(opts, :token)

    api_opts = [repo_type: :dataset]
    api_opts = if token, do: Keyword.put(api_opts, :token, token), else: api_opts

    case HfHub.Api.list_files(repo_id, api_opts) do
      {:ok, all_files} ->
        # Filter by config/split path patterns
        files =
          all_files
          |> filter_by_config(config)
          |> filter_by_split(split)
          |> Enum.map(&to_file_info/1)

        {:ok, files}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def download(repo_id, file_path, opts) do
    token = Keyword.get(opts, :token)

    download_opts = [
      repo_id: repo_id,
      filename: file_path,
      repo_type: :dataset
    ]

    download_opts = if token, do: Keyword.put(download_opts, :token, token), else: download_opts

    case HfHub.Download.hf_hub_download(download_opts) do
      {:ok, local_path} -> {:ok, local_path}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def stream(repo_id, file_path, opts) do
    token = Keyword.get(opts, :token)

    stream_opts = [
      repo_id: repo_id,
      filename: file_path,
      repo_type: :dataset
    ]

    stream_opts = if token, do: Keyword.put(stream_opts, :token, token), else: stream_opts

    # download_stream always returns {:ok, stream}
    HfHub.Download.download_stream(stream_opts)
  end

  @impl true
  def exists?(repo_id, opts) do
    token = Keyword.get(opts, :token)

    api_opts = []
    api_opts = if token, do: Keyword.put(api_opts, :token, token), else: api_opts

    case HfHub.Api.dataset_info(repo_id, api_opts) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # Private helpers

  defp filter_by_config(files, nil), do: files

  defp filter_by_config(files, config) do
    # Try to find files in config subdirectory or with config in name
    config_files =
      Enum.filter(files, fn file ->
        path = extract_path(file)

        path != nil and
          (String.contains?(path, "/#{config}/") or String.starts_with?(path, "#{config}/"))
      end)

    if Enum.empty?(config_files), do: files, else: config_files
  end

  defp filter_by_split(files, nil), do: files

  defp filter_by_split(files, split) do
    split_str = to_string(split)

    split_files =
      Enum.filter(files, fn file ->
        path = extract_path(file)

        path != nil and
          (String.contains?(path, split_str) or
             String.contains?(path, "/#{split_str}/") or
             String.contains?(path, "-#{split_str}"))
      end)

    if Enum.empty?(split_files), do: files, else: split_files
  end

  defp extract_path(file) when is_map(file) do
    file["path"] || file[:path] || file["rfilename"] || file[:rfilename]
  end

  defp extract_path(file) when is_binary(file), do: file
  defp extract_path(_), do: nil

  defp to_file_info(file) when is_map(file) do
    path = file["path"] || file[:path] || ""

    %{
      path: path,
      size: file["size"] || file[:size],
      format: Source.detect_format(path)
    }
  end

  defp to_file_info(file) when is_binary(file) do
    %{
      path: file,
      size: nil,
      format: Source.detect_format(file)
    }
  end
end
