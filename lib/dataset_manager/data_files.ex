defmodule HfDatasetsEx.DataFiles do
  @moduledoc """
  Resolve dataset file paths by config and split using HuggingFace Hub metadata.

  Uses HfHub.Api.dataset_configs/2, HfHub.Api.dataset_splits/2, and
  HfHub.Api.list_repo_tree/2 to infer configs and map split names to file paths.
  """

  alias HfDatasetsEx.Format

  @type file_info :: %{
          path: String.t(),
          format: atom(),
          size: non_neg_integer() | nil
        }

  @type resolved :: %{
          config: String.t() | nil,
          splits: %{String.t() => [file_info()]}
        }

  @doc """
  Resolve dataset file paths for each split.

  ## Options
    * `:config` - Dataset config name (optional)
    * `:split` - Dataset split name (optional)
    * `:revision` - Git revision (default: "main")
    * `:token` - HuggingFace token

  """
  @spec resolve(String.t(), keyword()) :: {:ok, resolved()} | {:error, term()}
  def resolve(repo_id, opts \\ []) when is_binary(repo_id) do
    config_opt = Keyword.get(opts, :config)
    split_opt = Keyword.get(opts, :split)
    revision = Keyword.get(opts, :revision, "main")
    token = Keyword.get(opts, :token)

    with {:ok, tree} <-
           HfHub.Api.list_repo_tree(repo_id,
             repo_type: :dataset,
             revision: revision,
             token: token,
             recursive: true
           ) do
      configs = fetch_configs(repo_id, revision, token)
      config = config_opt || default_config(configs, tree)
      splits = resolve_splits(repo_id, config, tree, split_opt, revision, token)

      case split_opt && Map.get(splits, to_string(split_opt)) do
        nil when split_opt != nil ->
          {:error, {:split_not_found, split_opt}}

        _ ->
          {:ok, %{config: config, splits: splits}}
      end
    end
  end

  defp fetch_configs(repo_id, revision, token) do
    case HfHub.Api.dataset_configs(repo_id, revision: revision, token: token) do
      {:ok, configs} -> configs
      {:error, _} -> []
    end
  end

  defp default_config([], tree) do
    tree_configs = HfHub.DatasetFiles.configs_from_tree(tree)
    pick_default_config(tree_configs)
  end

  defp default_config(configs, _tree) do
    pick_default_config(configs)
  end

  defp pick_default_config(configs) do
    cond do
      "default" in configs -> "default"
      "main" in configs -> "main"
      configs == [] -> nil
      true -> hd(configs)
    end
  end

  defp resolve_splits(repo_id, config, tree, split_opt, revision, token) do
    splits =
      if split_opt do
        [to_string(split_opt)]
      else
        splits_from_api(repo_id, config, revision, token, tree)
      end

    size_by_path = Map.new(tree, fn entry -> {entry.path, entry.size} end)

    splits
    |> Enum.reduce(%{}, fn split, acc ->
      case HfHub.DatasetFiles.resolve_from_tree(tree, config, split) do
        {:ok, paths} ->
          file_infos = Enum.map(paths, &file_info(&1, size_by_path))
          Map.put(acc, split, file_infos)

        {:error, _} ->
          acc
      end
    end)
  end

  defp splits_from_api(repo_id, config, revision, token, tree) do
    case HfHub.Api.dataset_splits(repo_id, config: config, revision: revision, token: token) do
      {:ok, splits} when splits != [] ->
        splits

      _ ->
        splits = HfHub.DatasetFiles.splits_from_tree(tree, config)
        if splits == [], do: ["train"], else: splits
    end
  end

  defp file_info(path, size_by_path) do
    %{
      path: path,
      format: Format.detect(path),
      size: Map.get(size_by_path, path)
    }
  end
end
