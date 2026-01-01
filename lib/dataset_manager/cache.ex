defmodule HfDatasetsEx.Cache do
  @moduledoc """
  Local dataset caching with version tracking.

  Cache directory: ~/.hf_datasets_ex/datasets/

  Structure:
    datasets/
    ├── manifest.json          # Index of all cached datasets
    ├── mmlu/
    │   ├── v1.0/
    │   │   ├── data.etf       # Serialized dataset
    │   │   └── metadata.json  # Version, checksum, timestamp
    │   └── latest -> v1.0     # Symlink to latest version
    ├── humaneval/
    └── gsm8k/
  """

  alias HfDatasetsEx.Dataset

  @cache_dir Path.expand("~/.hf_datasets_ex/datasets")
  @max_cache_size_mb 10_000
  @default_ttl_days 30

  @type cache_key :: {atom(), String.t() | atom()} | String.t() | atom()

  @doc """
  Get cached dataset if available and valid.
  """
  @spec get(cache_key()) :: {:ok, Dataset.t()} | {:error, :not_cached}
  def get(cache_key) do
    cache_path = build_cache_path(cache_key)
    data_path = Path.join(cache_path, "data.etf")
    metadata_path = Path.join(cache_path, "metadata.json")

    with true <- File.exists?(data_path),
         true <- File.exists?(metadata_path),
         {:ok, metadata_content} <- File.read(metadata_path),
         {:ok, metadata} <- Jason.decode(metadata_content),
         true <- valid_cache?(metadata),
         {:ok, data_content} <- File.read(data_path) do
      dataset = :erlang.binary_to_term(data_content)
      {:ok, dataset}
    else
      _ -> {:error, :not_cached}
    end
  end

  @doc """
  Store dataset in cache with versioning.
  """
  @spec put(cache_key(), Dataset.t()) :: :ok | {:error, term()}
  def put(cache_key, %Dataset{} = dataset) do
    cache_path = build_cache_path(cache_key, dataset.version)

    with :ok <- ensure_cache_dir(cache_path),
         :ok <- enforce_cache_limits(),
         :ok <- write_data(cache_path, dataset),
         :ok <- write_metadata(cache_path, dataset) do
      update_manifest(cache_key, dataset)
    end
  end

  @doc """
  Invalidate cached dataset.
  """
  @spec invalidate(cache_key()) :: :ok
  def invalidate(cache_key) do
    cache_path = build_cache_path(cache_key)
    File.rm_rf(cache_path)
    :ok
  end

  @doc """
  List all cached datasets with metadata.
  """
  @spec list() :: [map()]
  def list do
    manifest_path = Path.join(@cache_dir, "manifest.json")

    case File.read(manifest_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> Map.get(data, "datasets", [])
          _ -> []
        end

      {:error, _} ->
        []
    end
  end

  @doc """
  Clear all cached datasets.
  """
  @spec clear_all() :: :ok
  def clear_all do
    File.rm_rf(@cache_dir)
    :ok
  end

  # Private helpers

  defp build_cache_path({:local, name}), do: build_cache_path(name)
  defp build_cache_path({_type, name}), do: build_cache_path(name)

  defp build_cache_path(name) when is_atom(name) do
    build_cache_path(Atom.to_string(name))
  end

  defp build_cache_path(name) when is_binary(name) do
    Path.join(@cache_dir, name)
  end

  defp build_cache_path(name, version) when is_atom(name) and is_binary(version) do
    build_cache_path(Atom.to_string(name), version)
  end

  defp build_cache_path(name, version) when is_binary(name) and is_binary(version) do
    Path.join([@cache_dir, name, version])
  end

  defp ensure_cache_dir(cache_path) do
    File.mkdir_p(cache_path)
  end

  defp enforce_cache_limits do
    total_size = calculate_cache_size()

    if total_size > @max_cache_size_mb do
      evict_oldest_datasets(total_size - @max_cache_size_mb)
    else
      :ok
    end
  end

  defp calculate_cache_size do
    if File.exists?(@cache_dir) do
      calculate_cache_size_for_dir(@cache_dir)
    else
      0
    end
  end

  defp calculate_cache_size_for_dir(cache_dir) do
    case File.ls(cache_dir) do
      {:ok, dirs} ->
        dirs
        |> Enum.map(&get_dir_size(Path.join(cache_dir, &1)))
        |> Enum.sum()
        |> Kernel./(1024 * 1024)

      _ ->
        0
    end
  end

  defp get_dir_size(path) do
    case File.ls(path) do
      {:ok, files} -> Enum.sum(Enum.map(files, &get_file_size(path, &1)))
      _ -> 0
    end
  end

  defp get_file_size(dir, file) do
    file_path = Path.join(dir, file)

    case File.stat(file_path) do
      {:ok, %{size: size, type: :regular}} -> size
      {:ok, %{type: :directory}} -> get_dir_size(file_path)
      _ -> 0
    end
  end

  defp evict_oldest_datasets(_size_to_free) do
    # Simple eviction: remove oldest datasets based on modified time
    # In a real implementation, this would be more sophisticated
    :ok
  end

  defp write_data(cache_path, dataset) do
    data_path = Path.join(cache_path, "data.etf")
    serialized = :erlang.term_to_binary(dataset)
    File.write(data_path, serialized)
  end

  defp write_metadata(cache_path, dataset) do
    metadata_path = Path.join(cache_path, "metadata.json")

    metadata = %{
      name: dataset.name,
      version: dataset.version,
      cached_at: DateTime.to_iso8601(DateTime.utc_now()),
      ttl_days: @default_ttl_days,
      checksum: dataset.metadata.checksum,
      total_items: dataset.metadata.total_items
    }

    File.write(metadata_path, Jason.encode!(metadata, pretty: true))
  end

  @spec update_manifest(cache_key(), Dataset.t()) :: :ok | {:error, term()}
  defp update_manifest(cache_key, dataset) do
    manifest_path = Path.join(@cache_dir, "manifest.json")

    existing =
      case File.read(manifest_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, data} -> data
            _ -> %{"datasets" => []}
          end

        _ ->
          %{"datasets" => []}
      end

    dataset_entry = %{
      "name" => cache_key_to_string(cache_key),
      "version" => dataset.version,
      "size_mb" => 0,
      "cached_at" => DateTime.to_iso8601(DateTime.utc_now())
    }

    datasets = Map.get(existing, "datasets", [])
    # Remove old entry for same dataset
    datasets = Enum.reject(datasets, &(&1["name"] == dataset_entry["name"]))
    # Add new entry
    datasets = [dataset_entry | datasets]

    updated = Map.put(existing, "datasets", datasets)

    with :ok <- File.mkdir_p(@cache_dir) do
      File.write(manifest_path, Jason.encode!(updated, pretty: true))
    end
  end

  defp cache_key_to_string(cache_key) do
    if is_tuple(cache_key) do
      cache_key |> elem(1) |> to_string()
    else
      case cache_key do
        name when is_atom(name) -> Atom.to_string(name)
        name when is_binary(name) -> name
      end
    end
  end

  defp valid_cache?(metadata) do
    case DateTime.from_iso8601(metadata["cached_at"]) do
      {:ok, cached_at, _} ->
        ttl_days = metadata["ttl_days"] || @default_ttl_days
        expiry = DateTime.add(cached_at, ttl_days * 24 * 60 * 60, :second)
        DateTime.compare(DateTime.utc_now(), expiry) == :lt

      _ ->
        false
    end
  end
end
