defmodule HfDatasetsEx.Loader.Code do
  @moduledoc """
  Loader for code generation and understanding datasets.

  Supports:
    - DeepCoder (agentica-org/DeepCoder-Preview-Dataset)
    - HumanEval (openai/human-eval) - uses existing implementation

  ## Examples

      # Load DeepCoder
      {:ok, dataset} = HfDatasetsEx.Loader.Code.load(:deepcoder)

  """

  alias HfDatasetsEx.Dataset
  alias HfDatasetsEx.Fetcher.HuggingFace

  @datasets %{
    deepcoder: %{
      repo_id: "agentica-org/DeepCoder-Preview-Dataset",
      description: "DeepCoder code generation dataset"
    }
  }

  @doc """
  Load a code generation dataset.

  ## Arguments
    * `dataset_name` - Currently supports `:deepcoder`
    * `opts` - Options (see below)

  ## Options
    * `:split` - Dataset split (default: "train")
    * `:config` - Dataset config/subset (e.g., "primeintellect")
    * `:sample_size` - Limit number of items
    * `:token` - HuggingFace API token

  """
  @spec load(atom(), keyword()) :: {:ok, Dataset.t()} | {:error, term()}
  def load(dataset_name, opts \\ [])

  def load(dataset_name, opts) when is_atom(dataset_name) do
    case Map.get(@datasets, dataset_name) do
      nil ->
        {:error, {:unknown_dataset, dataset_name, Map.keys(@datasets)}}

      dataset_info ->
        load_from_huggingface(dataset_name, dataset_info, opts)
    end
  end

  defp load_from_huggingface(dataset_name, %{repo_id: repo_id}, opts) do
    split = Keyword.get(opts, :split, "train") |> to_string()
    config = Keyword.get(opts, :config)
    sample_size = Keyword.get(opts, :sample_size)
    token = Keyword.get(opts, :token)

    fetch_opts = [split: split, token: token]
    fetch_opts = if config, do: Keyword.put(fetch_opts, :config, config), else: fetch_opts

    case HuggingFace.fetch(repo_id, fetch_opts) do
      {:ok, raw_data} ->
        items = parse_code_data(raw_data, dataset_name)

        items = if sample_size, do: Enum.take(items, sample_size), else: items

        dataset =
          Dataset.new(
            to_string(dataset_name),
            "1.0",
            items,
            %{
              source: "huggingface:#{repo_id}",
              split: split,
              license: "apache-2.0",
              domain: "code"
            }
          )

        {:ok, dataset}

      {:error, reason} ->
        {:error, {:huggingface_fetch_failed, reason}}
    end
  end

  defp parse_code_data(raw_data, :deepcoder) do
    raw_data
    |> Enum.with_index()
    |> Enum.map(fn {item, idx} ->
      %{
        id: "deepcoder_#{idx}",
        input: %{
          problem: item["problem"] || item["prompt"] || item["instruction"],
          language: item["language"] || "python"
        },
        expected: item["solution"] || item["code"] || item["response"],
        metadata: %{
          source: item["source"],
          difficulty: item["difficulty"],
          tags: item["tags"]
        }
      }
    end)
  end

  @doc """
  List available code datasets.
  """
  @spec available_datasets() :: [atom()]
  def available_datasets, do: Map.keys(@datasets)
end
