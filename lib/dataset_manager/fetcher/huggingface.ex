defmodule HfDatasetsEx.Fetcher.HuggingFace do
  @moduledoc """
  HuggingFace Hub API client for dataset downloads.

  This module provides a high-level interface for fetching datasets from HuggingFace Hub,
  built on top of the `HfHub` library which handles API access, downloads, and caching.

  ## Features

  - List files in a HuggingFace dataset repository
  - Download individual files with automatic caching
  - Fetch and parse complete dataset splits (parquet, jsonl, json, csv)
  - Resume interrupted downloads
  - Smart caching with LRU eviction

  ## Authentication

  Set the `HF_TOKEN` environment variable for authenticated access to private datasets,
  or configure via:

      config :hf_hub, token: "hf_..."

  ## Examples

      # List files in a dataset
      {:ok, files} = HuggingFace.list_files("openai/gsm8k")

      # Download a specific file
      {:ok, path} = HuggingFace.download_file("openai/gsm8k", "data/train.parquet")

      # Fetch and parse a dataset split
      {:ok, rows} = HuggingFace.fetch("openai/gsm8k", split: "train")

      # Get dataset configurations
      {:ok, configs} = HuggingFace.dataset_configs("openai/gsm8k")

  """

  require Logger

  @doc """
  Build the download URL for a file in a HuggingFace dataset.

  ## Examples

      iex> HuggingFace.build_file_url("openai/gsm8k", "data/train.parquet")
      "https://huggingface.co/datasets/openai/gsm8k/resolve/main/data/train.parquet"

  """
  @spec build_file_url(String.t(), String.t(), keyword()) :: String.t()
  def build_file_url(repo_id, path, opts \\ []) do
    revision = Keyword.get(opts, :revision, "main")
    endpoint = HfHub.Config.endpoint()
    "#{endpoint}/datasets/#{repo_id}/resolve/#{revision}/#{path}"
  end

  @doc """
  List all files in a HuggingFace dataset repository.

  ## Options
    * `:config` - Dataset configuration/subset (filters by path prefix)
    * `:revision` - Git revision/branch (default: "main")
    * `:token` - HuggingFace API token (default: from HF_TOKEN env var or hf_hub config)

  ## Returns
    * `{:ok, files}` - List of file metadata maps with "path", "size", "type" keys
    * `{:error, reason}` - Error tuple

  """
  @spec list_files(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def list_files(repo_id, opts \\ []) do
    config = Keyword.get(opts, :config)
    revision = Keyword.get(opts, :revision, "main")
    token = Keyword.get(opts, :token)

    case HfHub.Api.list_files(repo_id, repo_type: :dataset, revision: revision, token: token) do
      {:ok, files} ->
        # Convert HfHub file_info format to our expected format
        formatted_files =
          files
          |> Enum.map(fn file ->
            %{
              "path" => file.rfilename,
              "size" => file.size,
              "type" => if(String.contains?(file.rfilename || "", "/"), do: "file", else: "file"),
              "lfs" => file.lfs
            }
          end)
          |> maybe_filter_by_config(config)

        {:ok, formatted_files}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_filter_by_config(files, nil), do: files

  defp maybe_filter_by_config(files, config) do
    Enum.filter(files, fn f ->
      path = f["path"] || ""

      String.starts_with?(path, config) or
        String.starts_with?(path, "data/#{config}") or
        String.contains?(path, "/#{config}/")
    end)
  end

  @doc """
  Download a file from a HuggingFace dataset repository.

  Downloads to the HfHub cache and returns the file contents. Uses caching by default,
  so repeated downloads of the same file are served from cache.

  ## Options
    * `:revision` - Git revision/branch (default: "main")
    * `:token` - HuggingFace API token (default: from hf_hub config)
    * `:force_download` - Force re-download even if cached (default: false)

  ## Returns
    * `{:ok, binary}` - File contents as binary
    * `{:error, reason}` - Error tuple

  """
  @spec download_file(String.t(), String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def download_file(repo_id, path, opts \\ []) do
    revision = Keyword.get(opts, :revision, "main")
    token = Keyword.get(opts, :token)
    force_download = Keyword.get(opts, :force_download, false)

    download_opts = [
      repo_id: repo_id,
      filename: path,
      repo_type: :dataset,
      revision: revision,
      force_download: force_download
    ]

    download_opts = if token, do: Keyword.put(download_opts, :token, token), else: download_opts

    case HfHub.Download.hf_hub_download(download_opts) do
      {:ok, cache_path} ->
        # Read the file contents from cache
        case File.read(cache_path) do
          {:ok, ""} ->
            # Empty file likely means download failed (404 created empty file)
            {:error, :empty_file}

          {:ok, data} ->
            {:ok, data}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Download a file and return the local cache path instead of contents.

  Useful for large files where you don't want to load the entire file into memory.

  ## Options
    * `:revision` - Git revision/branch (default: "main")
    * `:token` - HuggingFace API token
    * `:force_download` - Force re-download even if cached (default: false)

  ## Returns
    * `{:ok, path}` - Local path to the cached file
    * `{:error, reason}` - Error tuple

  """
  @spec download_file_to_cache(String.t(), String.t(), keyword()) ::
          {:ok, Path.t()} | {:error, term()}
  def download_file_to_cache(repo_id, path, opts \\ []) do
    revision = Keyword.get(opts, :revision, "main")
    token = Keyword.get(opts, :token)
    force_download = Keyword.get(opts, :force_download, false)

    download_opts = [
      repo_id: repo_id,
      filename: path,
      repo_type: :dataset,
      revision: revision,
      force_download: force_download
    ]

    download_opts = if token, do: Keyword.put(download_opts, :token, token), else: download_opts

    HfHub.Download.hf_hub_download(download_opts)
  end

  @doc """
  Fetch and parse a complete dataset split from HuggingFace.

  This is the main function for loading datasets. It:
  1. Lists files in the repository
  2. Finds parquet/jsonl files matching the requested split
  3. Downloads and parses the files
  4. Returns the data as a list of maps

  ## Options
    * `:split` - Dataset split (default: "train")
    * `:config` - Dataset configuration/subset
    * `:revision` - Git revision/branch (default: "main")
    * `:token` - HuggingFace API token (default: from HF_TOKEN env var)
    * `:max_files` - Maximum number of files to download for sharded datasets (default: 3)

  ## Returns
    * `{:ok, data}` - List of row maps
    * `{:error, reason}` - Error tuple

  ## Examples

      {:ok, data} = HuggingFace.fetch("openai/gsm8k", split: "train")
      {:ok, data} = HuggingFace.fetch("cais/mmlu", config: "astronomy", split: "test")

  """
  @spec fetch(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def fetch(repo_id, opts \\ []) do
    split = Keyword.get(opts, :split, "train")
    config = Keyword.get(opts, :config)
    token = Keyword.get(opts, :token)
    revision = Keyword.get(opts, :revision, "main")
    # Limit files for large sharded datasets (default: 3 files max)
    max_files = Keyword.get(opts, :max_files, 3)

    with {:ok, %{splits: splits}} <-
           HfDatasetsEx.DataFiles.resolve(repo_id,
             config: config,
             split: split,
             revision: revision,
             token: token
           ),
         files when is_list(files) <- Map.get(splits, to_string(split)),
         true <- files != [],
         limited_files = Enum.take(files, max_files),
         {:ok, data} <- download_and_parse_files(repo_id, limited_files, revision, token) do
      {:ok, data}
    else
      nil -> {:error, {:split_not_found, split}}
      false -> {:error, {:split_not_found, split}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get dataset information from HuggingFace Hub.

  ## Options
    * `:revision` - Git revision/branch (default: "main")
    * `:token` - HuggingFace API token

  ## Returns
    * `{:ok, info}` - Dataset metadata map
    * `{:error, reason}` - Error tuple

  """
  @spec dataset_info(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def dataset_info(repo_id, opts \\ []) do
    HfHub.Api.dataset_info(repo_id, opts)
  end

  @doc """
  Get available configuration names for a dataset.

  Configurations (also called subsets) represent different versions of a dataset.
  For example, `openai/gsm8k` has "main" and "socratic" configs.

  ## Options
    * `:token` - HuggingFace API token

  ## Returns
    * `{:ok, configs}` - List of configuration names
    * `{:error, reason}` - Error tuple

  ## Examples

      {:ok, configs} = HuggingFace.dataset_configs("openai/gsm8k")
      # => {:ok, ["main", "socratic"]}

  """
  @spec dataset_configs(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def dataset_configs(repo_id, opts \\ []) do
    HfHub.Api.dataset_configs(repo_id, opts)
  end

  @doc """
  Check if a dataset file is cached locally.

  ## Options
    * `:revision` - Git revision/branch (default: "main")

  ## Returns
    * `true` if the file is cached, `false` otherwise

  """
  @spec cached?(String.t(), String.t(), keyword()) :: boolean()
  def cached?(repo_id, filename, opts \\ []) do
    revision = Keyword.get(opts, :revision, "main")

    HfHub.Cache.cached?(
      repo_id: repo_id,
      filename: filename,
      repo_type: :dataset,
      revision: revision
    )
  end

  @doc """
  Get the local cache path for a dataset file.

  ## Options
    * `:revision` - Git revision/branch (default: "main")

  ## Returns
    * `{:ok, path}` - Local path to the cached file
    * `{:error, :not_cached}` - File is not cached

  """
  @spec cache_path(String.t(), String.t(), keyword()) :: {:ok, Path.t()} | {:error, :not_cached}
  def cache_path(repo_id, filename, opts \\ []) do
    revision = Keyword.get(opts, :revision, "main")

    HfHub.Cache.cache_path(
      repo_id: repo_id,
      filename: filename,
      repo_type: :dataset,
      revision: revision
    )
  end

  # Private helpers

  defp download_and_parse_files(repo_id, files, revision, token) do
    results =
      Enum.map(files, fn file ->
        path = file.path

        download_opts = [
          repo_id: repo_id,
          filename: path,
          repo_type: :dataset,
          revision: revision,
          token: token,
          extract: true
        ]

        result =
          with {:ok, local_path} <- HfHub.Download.hf_hub_download(download_opts) do
            parse_downloaded_path(local_path, file.format)
          end

        case result do
          {:error, reason} ->
            Logger.warning("Failed to download/parse #{path}: #{inspect(reason)}")
            []

          rows when is_list(rows) ->
            rows

          {:ok, rows} when is_list(rows) ->
            rows
        end
      end)

    all_rows = List.flatten(results)

    if all_rows == [] do
      {:error, :no_data_parsed}
    else
      {:ok, all_rows}
    end
  end

  defp parse_downloaded_path(path, format_hint) do
    paths =
      if File.dir?(path) do
        Path.wildcard(Path.join(path, "**/*"))
        |> Enum.reject(&File.dir?/1)
      else
        [path]
      end

    results =
      Enum.map(paths, fn file_path ->
        format =
          if format_hint == :unknown do
            HfDatasetsEx.Format.detect(file_path)
          else
            format_hint
          end

        parser = HfDatasetsEx.Format.parser_for(format)

        if is_nil(parser) do
          {:ok, []}
        else
          apply(parser, :parse, [file_path])
        end
      end)

    merge_parse_results(results)
  end

  defp merge_parse_results(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn result, {:ok, acc} ->
      case result do
        {:ok, items} -> {:cont, {:ok, acc ++ items}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
