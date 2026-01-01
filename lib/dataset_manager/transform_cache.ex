defmodule HfDatasetsEx.TransformCache do
  @moduledoc """
  Caches dataset transformation results based on fingerprints.
  """

  alias HfDatasetsEx.{Config, Dataset, Fingerprint}

  @manifest_file "manifest.json"

  @type cache_key :: String.t()

  @doc """
  Look up a cached transformation result.

  Returns {:ok, dataset} if found, :miss otherwise.
  """
  @spec get(Fingerprint.t(), Fingerprint.t()) :: {:ok, Dataset.t()} | :miss
  def get(input_fp, transform_fp) do
    key = cache_key(input_fp, transform_fp)
    path = cache_path(key)

    if File.exists?(path) do
      try do
        dataset = path |> File.read!() |> :erlang.binary_to_term()
        {:ok, dataset}
      rescue
        _ -> :miss
      end
    else
      :miss
    end
  end

  @doc """
  Store a transformation result in cache.
  """
  @spec put(Fingerprint.t(), Fingerprint.t(), Dataset.t()) :: :ok
  def put(input_fp, transform_fp, dataset) do
    key = cache_key(input_fp, transform_fp)
    path = cache_path(key)

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary(dataset))

    update_manifest(key, %{
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      input_fingerprint: input_fp,
      transform_fingerprint: transform_fp,
      num_items: Dataset.num_items(dataset),
      size_bytes: File.stat!(path).size
    })

    :ok
  end

  @doc """
  Clean up old cache entries.

  ## Options

    * `:max_age_days` - Remove entries older than this (default: 30)
    * `:max_size_bytes` - Maximum total cache size (default: 10GB)

  """
  @spec cleanup(keyword()) :: {:ok, non_neg_integer()}
  def cleanup(opts \\ []) do
    max_age_days = Keyword.get(opts, :max_age_days, 30)
    max_size_bytes = Keyword.get(opts, :max_size_bytes, 10 * 1024 * 1024 * 1024)

    manifest = load_manifest()
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days, :day)

    {expired, valid} =
      Enum.split_with(manifest, fn {_key, meta} ->
        {:ok, created, _} = DateTime.from_iso8601(meta["created_at"])
        DateTime.compare(created, cutoff) == :lt
      end)

    deleted_count =
      expired
      |> Enum.map(fn {key, _} ->
        path = cache_path(key)
        File.rm(path)
        key
      end)
      |> length()

    remaining = delete_until_under_size(valid, max_size_bytes)
    save_manifest(Map.new(remaining))

    {:ok, deleted_count}
  end

  @doc """
  Clear entire transform cache.
  """
  @spec clear_all() :: :ok
  def clear_all do
    File.rm_rf!(cache_dir())
    File.mkdir_p!(cache_dir())
    :ok
  end

  @doc """
  Get cache statistics.
  """
  @spec stats() :: map()
  def stats do
    manifest = load_manifest()

    total_size =
      manifest
      |> Map.values()
      |> Enum.map(& &1["size_bytes"])
      |> Enum.sum()

    %{
      entry_count: map_size(manifest),
      total_size_bytes: total_size,
      cache_dir: cache_dir()
    }
  end

  defp cache_dir do
    Application.get_env(
      :hf_datasets_ex,
      :transform_cache_dir,
      Path.join(Config.cache_dir(), "transforms")
    )
  end

  defp cache_key(input_fp, transform_fp) do
    "#{String.slice(input_fp, 0, 16)}_#{String.slice(transform_fp, 0, 16)}"
  end

  defp cache_path(key) do
    Path.join(cache_dir(), "#{key}.cache")
  end

  defp manifest_path do
    Path.join(cache_dir(), @manifest_file)
  end

  defp load_manifest do
    path = manifest_path()

    if File.exists?(path) do
      path |> File.read!() |> Jason.decode!()
    else
      %{}
    end
  end

  defp save_manifest(manifest) do
    File.mkdir_p!(cache_dir())
    File.write!(manifest_path(), Jason.encode!(manifest, pretty: true))
  end

  defp update_manifest(key, meta) do
    manifest = load_manifest()
    updated = Map.put(manifest, key, meta)
    save_manifest(updated)
  end

  defp delete_until_under_size(entries, max_size) do
    total =
      entries
      |> Enum.map(fn {_, m} -> m["size_bytes"] || 0 end)
      |> Enum.sum()

    if total <= max_size do
      entries
    else
      sorted =
        entries
        |> Enum.sort_by(fn {_, m} -> m["created_at"] end)

      delete_until_under_size_loop(sorted, total, max_size)
    end
  end

  defp delete_until_under_size_loop([], _total, _max), do: []
  defp delete_until_under_size_loop(entries, total, max) when total <= max, do: entries

  defp delete_until_under_size_loop([{key, meta} | rest], total, max) do
    File.rm(cache_path(key))
    delete_until_under_size_loop(rest, total - (meta["size_bytes"] || 0), max)
  end
end
