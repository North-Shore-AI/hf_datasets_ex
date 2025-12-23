defmodule HfDatasetsEx.Loader.Chat do
  @moduledoc """
  Loader for chat/instruction-following datasets.

  Supports:
    - Tulu-3-SFT (allenai/tulu-3-sft-mixture)
    - No Robots (HuggingFaceH4/no_robots)

  ## Examples

      # Load Tulu-3-SFT
      {:ok, dataset} = HfDatasetsEx.Loader.Chat.load(:tulu3_sft)

      # Load No Robots
      {:ok, dataset} = HfDatasetsEx.Loader.Chat.load(:no_robots)

  """

  alias HfDatasetsEx.Dataset
  alias HfDatasetsEx.Fetcher.HuggingFace
  alias HfDatasetsEx.Types.Conversation

  @datasets %{
    tulu3_sft: %{
      repo_id: "allenai/tulu-3-sft-mixture",
      description: "Tulu 3 SFT Mixture - instruction-following dataset"
    },
    no_robots: %{
      repo_id: "HuggingFaceH4/no_robots",
      description: "No Robots - high-quality human demonstrations"
    }
  }

  @doc """
  Load a chat/instruction-following dataset.

  ## Arguments
    * `dataset_name` - Either `:tulu3_sft` or `:no_robots`
    * `opts` - Options (see below)

  ## Options
    * `:split` - Dataset split (default: "train")
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
    sample_size = Keyword.get(opts, :sample_size)
    token = Keyword.get(opts, :token)

    case HuggingFace.fetch(repo_id, split: split, token: token) do
      {:ok, raw_data} ->
        items = parse_chat_data(raw_data, dataset_name)

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
              domain: "chat"
            }
          )

        {:ok, dataset}

      {:error, reason} ->
        {:error, {:huggingface_fetch_failed, reason}}
    end
  end

  defp parse_chat_data(raw_data, _dataset_name) do
    raw_data
    |> Enum.with_index()
    |> Enum.map(fn {item, idx} ->
      messages = item["messages"] || item["conversations"] || []

      case Conversation.from_hf_data(messages, %{source: item["source"]}) do
        {:ok, conversation} ->
          %{
            id: "chat_#{idx}",
            input: %{
              conversation: conversation
            },
            expected: nil,
            metadata: %{
              source: item["source"] || "unknown",
              turn_count: Conversation.turn_count(conversation)
            }
          }

        {:error, _} ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  List available chat datasets.
  """
  @spec available_datasets() :: [atom()]
  def available_datasets, do: Map.keys(@datasets)
end
