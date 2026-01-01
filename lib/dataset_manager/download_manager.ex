defmodule HfDatasetsEx.DownloadManager do
  @moduledoc """
  Manages file downloads and extraction for dataset builders.
  """

  @type t :: %__MODULE__{
          cache_dir: Path.t(),
          download_config: map()
        }

  defstruct [:cache_dir, :download_config]

  @default_cache_dir Path.expand("~/.hf_datasets_ex/downloads")

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      cache_dir: Keyword.get(opts, :cache_dir, @default_cache_dir),
      download_config: Keyword.get(opts, :download_config, %{})
    }
  end

  @doc """
  Download a file and return its local path.

  Caches downloads by URL hash.
  """
  @spec download(t(), String.t()) :: {:ok, Path.t()} | {:error, term()}
  def download(%__MODULE__{cache_dir: cache_dir}, url) do
    cache_path = url_to_cache_path(cache_dir, url)

    if File.exists?(cache_path) do
      {:ok, cache_path}
    else
      File.mkdir_p!(Path.dirname(cache_path))
      do_download(url, cache_path)
    end
  end

  @doc """
  Download and extract an archive.

  Returns path to extracted directory.
  """
  @spec download_and_extract(t(), String.t()) :: {:ok, Path.t()} | {:error, term()}
  def download_and_extract(%__MODULE__{} = dm, url) do
    with {:ok, archive_path} <- download(dm, url) do
      extract_dir = archive_path <> "_extracted"

      if File.exists?(extract_dir) do
        {:ok, extract_dir}
      else
        extract(archive_path, extract_dir)
      end
    end
  end

  @doc """
  Download multiple files in parallel.
  """
  @spec download_many(t(), [String.t()]) :: {:ok, [Path.t()]} | {:error, term()}
  def download_many(%__MODULE__{} = dm, urls) do
    results =
      urls
      |> Task.async_stream(&download(dm, &1), max_concurrency: 8, timeout: 120_000)
      |> Enum.map(fn
        {:ok, {:ok, path}} -> {:ok, path}
        {:ok, {:error, e}} -> {:error, e}
        {:exit, reason} -> {:error, {:exit, reason}}
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      {:ok, Enum.map(results, fn {:ok, path} -> path end)}
    else
      {:error, {:download_failed, errors}}
    end
  end

  defp url_to_cache_path(cache_dir, url) do
    hash = :crypto.hash(:sha256, url) |> Base.encode16(case: :lower) |> String.slice(0, 16)
    path = url |> URI.parse() |> Map.get(:path, "")
    ext = archive_ext(path)

    Path.join(cache_dir, "#{hash}#{ext}")
  end

  defp archive_ext(path) do
    cond do
      String.ends_with?(path, ".tar.gz") -> ".tar.gz"
      String.ends_with?(path, ".tar.bz2") -> ".tar.bz2"
      String.ends_with?(path, ".tar.xz") -> ".tar.xz"
      true -> Path.extname(path)
    end
  end

  defp do_download(url, dest_path) do
    # Use httpc or Req
    case :httpc.request(:get, {to_charlist(url), []}, [], body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        File.write!(dest_path, body)
        {:ok, dest_path}

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract(archive_path, extract_dir) do
    File.mkdir_p!(extract_dir)

    result =
      cond do
        String.ends_with?(archive_path, ".tar.gz") or String.ends_with?(archive_path, ".tgz") ->
          :erl_tar.extract(
            to_charlist(archive_path),
            [:compressed, {:cwd, to_charlist(extract_dir)}]
          )

        String.ends_with?(archive_path, ".zip") ->
          :zip.unzip(to_charlist(archive_path), [{:cwd, to_charlist(extract_dir)}])

        String.ends_with?(archive_path, ".gz") ->
          content = archive_path |> File.read!() |> :zlib.gunzip()
          output = Path.join(extract_dir, Path.basename(archive_path, ".gz"))
          File.write!(output, content)
          :ok

        true ->
          {:error, {:unknown_archive_type, archive_path}}
      end

    case result do
      :ok -> {:ok, extract_dir}
      {:ok, _} -> {:ok, extract_dir}
      error -> error
    end
  end
end
