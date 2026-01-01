defmodule HfDatasetsEx.Builder do
  @moduledoc """
  Runs a dataset builder to produce a Dataset or DatasetDict.
  """

  alias HfDatasetsEx.{
    Dataset,
    DatasetDict,
    DownloadManager,
    SplitGenerator
  }

  @type build_opts :: [
          config_name: String.t() | nil,
          split: String.t() | atom() | nil,
          cache_dir: Path.t() | nil
        ]

  @doc """
  Build a dataset using a builder module.

  ## Options

    * `:config_name` - Config to use (default: first or default_config_name)
    * `:split` - Specific split to build (default: all)
    * `:cache_dir` - Cache directory for downloads

  ## Examples

      {:ok, dataset_dict} = Builder.build(MyDataset)
      {:ok, train} = Builder.build(MyDataset, split: :train)

  """
  @spec build(module(), build_opts()) :: {:ok, DatasetDict.t() | Dataset.t()} | {:error, term()}
  def build(builder_module, opts \\ []) do
    config_name = Keyword.get(opts, :config_name)
    requested_split = Keyword.get(opts, :split)
    cache_dir = Keyword.get(opts, :cache_dir)

    with {:ok, config} <- get_config(builder_module, config_name),
         dm = DownloadManager.new(cache_dir: cache_dir),
         split_gens = builder_module.split_generators(dm, config),
         {:ok, splits} <- generate_splits(builder_module, split_gens, requested_split) do
      info = builder_module.info()

      datasets =
        Map.new(splits, fn {split_name, items} ->
          dataset = %Dataset{
            name: "#{builder_module}:#{config.name}",
            version: config.version,
            items: items,
            features: info.features,
            metadata: %{
              description: info.description,
              citation: info.citation,
              license: info.license,
              builder: builder_module,
              config: config.name
            }
          }

          {to_string(split_name), dataset}
        end)

      result =
        if requested_split do
          # Return single dataset
          Map.values(datasets) |> hd()
        else
          # Return DatasetDict
          DatasetDict.new(datasets)
        end

      {:ok, result}
    end
  end

  defp get_config(builder_module, nil) do
    configs = builder_module.configs()
    default_name = builder_module.default_config_name()

    config =
      if default_name do
        Enum.find(configs, hd(configs), &(&1.name == default_name))
      else
        hd(configs)
      end

    {:ok, config}
  end

  defp get_config(builder_module, config_name) do
    configs = builder_module.configs()

    case Enum.find(configs, &(&1.name == config_name)) do
      nil ->
        available = Enum.map(configs, & &1.name)
        {:error, {:unknown_config, config_name, available}}

      config ->
        {:ok, config}
    end
  end

  defp generate_splits(builder_module, split_gens, requested_split) do
    filtered_gens = filter_split_gens(split_gens, requested_split)

    if filtered_gens == [] do
      {:error, :no_splits_found}
    else
      results = Enum.map(filtered_gens, &generate_split(builder_module, &1))
      {:ok, results}
    end
  end

  defp filter_split_gens(split_gens, nil), do: split_gens

  defp filter_split_gens(split_gens, requested_split) do
    split_atom = to_split_atom(requested_split)
    Enum.filter(split_gens, &(&1.name == split_atom))
  end

  defp to_split_atom(split) when is_binary(split), do: String.to_atom(split)
  defp to_split_atom(split), do: split

  defp generate_split(builder_module, %SplitGenerator{name: name, gen_kwargs: kwargs}) do
    items =
      builder_module.generate_examples(kwargs, name)
      |> Enum.map(&normalize_example/1)

    {name, items}
  end

  defp normalize_example({_idx, item}), do: item
  defp normalize_example(item) when is_map(item), do: item
end
