defmodule HfDatasetsEx.Config do
  @moduledoc """
  Configuration for hf_datasets_ex.
  """

  @defaults %{
    caching_enabled: true,
    cache_dir: "~/.hf_datasets_ex",
    max_cache_size_gb: 10,
    max_cache_age_days: 30
  }

  @doc """
  Get a configuration value.
  """
  @spec get(atom()) :: any()
  def get(key) do
    Application.get_env(:hf_datasets_ex, key, Map.get(@defaults, key))
  end

  @doc """
  Check if caching is enabled.
  """
  @spec caching_enabled?() :: boolean()
  def caching_enabled? do
    get(:caching_enabled) and not offline_mode?()
  end

  @doc """
  Check if running in offline mode.
  """
  @spec offline_mode?() :: boolean()
  def offline_mode? do
    System.get_env("HF_DATASETS_OFFLINE") == "1"
  end

  @doc """
  Get the cache directory path.
  """
  @spec cache_dir() :: Path.t()
  def cache_dir do
    get(:cache_dir) |> Path.expand()
  end
end
