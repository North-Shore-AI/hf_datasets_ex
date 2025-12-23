defmodule HfDatasetsEx.Loader.Reasoning do
  @moduledoc """
  Loader for reasoning/chain-of-thought datasets used in distillation.

  Supports:
    - OpenThoughts3 (open-thoughts/OpenThoughts3-1.2M)
    - DeepMath-103K (zwhe99/DeepMath-103K) - reasoning variant

  ## Examples

      # Load OpenThoughts3
      {:ok, dataset} = HfDatasetsEx.Loader.Reasoning.load(:open_thoughts3)

      # Load with sample size
      {:ok, dataset} = HfDatasetsEx.Loader.Reasoning.load(:open_thoughts3, sample_size: 1000)

  """

  alias HfDatasetsEx.Dataset
  alias HfDatasetsEx.Fetcher.HuggingFace
  alias HfDatasetsEx.Types.Conversation

  @datasets %{
    open_thoughts3: %{
      repo_id: "open-thoughts/OpenThoughts3-1.2M",
      parser: :open_thoughts,
      description: "OpenThoughts3 reasoning traces for distillation (1.2M examples)"
    },
    deepmath_reasoning: %{
      repo_id: "zwhe99/DeepMath-103K",
      parser: :deepmath,
      description: "DeepMath 103K with reasoning traces"
    }
  }

  @doc """
  Load a reasoning/chain-of-thought dataset.

  ## Arguments
    * `dataset_name` - One of `:open_thoughts3`, `:deepmath_reasoning`
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

  defp load_from_huggingface(dataset_name, %{repo_id: repo_id, parser: parser}, opts) do
    split = Keyword.get(opts, :split, "train") |> to_string()
    sample_size = Keyword.get(opts, :sample_size)
    token = Keyword.get(opts, :token)

    case HuggingFace.fetch(repo_id, split: split, token: token) do
      {:ok, raw_data} ->
        items = parse_reasoning_data(raw_data, parser)

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
              domain: "reasoning"
            }
          )

        {:ok, dataset}

      {:error, reason} ->
        {:error, {:huggingface_fetch_failed, reason}}
    end
  end

  defp parse_reasoning_data(raw_data, parser) do
    raw_data
    |> Enum.with_index()
    |> Enum.map(fn {item, idx} ->
      case parse_item(item, parser, idx) do
        {:ok, parsed_item} -> parsed_item
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_item(item, :open_thoughts, idx) do
    # OpenThoughts3 format: conversations with from/value pairs
    conversations = item["conversations"] || []

    messages =
      Enum.map(conversations, fn msg ->
        role =
          case msg["from"] do
            "human" -> :user
            "gpt" -> :assistant
            "system" -> :system
            _ -> :user
          end

        HfDatasetsEx.Types.Message.new(role, msg["value"] || "")
      end)

    case Conversation.new(messages) do
      conversation when is_struct(conversation) ->
        # Extract the user prompt (first user message)
        prompt = extract_first_user_message(conversations)

        # Extract the assistant reasoning (last assistant message)
        reasoning = extract_last_assistant_message(conversations)

        {:ok,
         %{
           id: "open_thoughts_#{idx}",
           input: %{
             prompt: prompt,
             conversation: conversation
           },
           expected: %{
             reasoning: reasoning
           },
           metadata: %{
             source: "open_thoughts3",
             turn_count: length(messages),
             has_reasoning: String.contains?(reasoning || "", ["<think>", "Let me", "First,"])
           }
         }}

      _ ->
        {:error, :invalid_conversation}
    end
  end

  defp parse_item(item, :deepmath, idx) do
    problem = item["problem"] || item["question"] || ""
    solution = item["solution"] || item["answer"] || ""

    {:ok,
     %{
       id: "deepmath_reasoning_#{idx}",
       input: %{
         prompt: problem
       },
       expected: %{
         reasoning: solution,
         answer: extract_final_answer(solution)
       },
       metadata: %{
         source: "deepmath",
         has_reasoning: String.length(solution) > 100
       }
     }}
  end

  defp extract_first_user_message(conversations) do
    conversations
    |> Enum.find(fn msg -> msg["from"] == "human" end)
    |> case do
      nil -> ""
      msg -> msg["value"] || ""
    end
  end

  defp extract_last_assistant_message(conversations) do
    conversations
    |> Enum.filter(fn msg -> msg["from"] == "gpt" end)
    |> List.last()
    |> case do
      nil -> ""
      msg -> msg["value"] || ""
    end
  end

  defp extract_final_answer(solution) when is_binary(solution) do
    # Try common answer patterns
    cond do
      String.contains?(solution, "####") ->
        solution |> String.split("####") |> List.last() |> String.trim()

      String.contains?(solution, "\\boxed{") ->
        case Regex.run(~r/\\boxed\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}/, solution) do
          [_, answer] -> String.trim(answer)
          nil -> nil
        end

      true ->
        nil
    end
  end

  defp extract_final_answer(_), do: nil

  @doc """
  List available reasoning datasets.
  """
  @spec available_datasets() :: [atom()]
  def available_datasets, do: Map.keys(@datasets)
end
