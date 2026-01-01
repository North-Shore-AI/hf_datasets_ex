defmodule HfDatasetsEx.Loader.Preference do
  @moduledoc """
  Loader for preference/comparison datasets used in DPO and RLHF.

  Supports:
    - HH-RLHF (Anthropic/hh-rlhf)
    - HelpSteer3 (nvidia/HelpSteer3)
    - HelpSteer2 (nvidia/HelpSteer2)
    - UltraFeedback (openbmb/UltraFeedback)
    - Arena-140K (lmarena-ai/arena-hard-v0.1)
    - Tulu-3-Preference (allenai/tulu-3-preference-mixture)

  ## Examples

      # Load HH-RLHF
      {:ok, dataset} = HfDatasetsEx.Loader.Preference.load(:hh_rlhf)

      # Load HelpSteer3
      {:ok, dataset} = HfDatasetsEx.Loader.Preference.load(:helpsteer3)

  """

  alias HfDatasetsEx.Dataset
  alias HfDatasetsEx.Fetcher.HuggingFace
  alias HfDatasetsEx.Types.{Comparison, LabeledComparison}

  @datasets %{
    hh_rlhf: %{
      repo_id: "Anthropic/hh-rlhf",
      parser: :hh_rlhf,
      description: "Anthropic's HH-RLHF dataset"
    },
    helpsteer3: %{
      repo_id: "nvidia/HelpSteer3",
      parser: :helpsteer,
      config: "preference",
      description: "NVIDIA HelpSteer3 dataset"
    },
    helpsteer2: %{
      repo_id: "nvidia/HelpSteer2",
      parser: :helpsteer2,
      description: "NVIDIA HelpSteer2 dataset"
    },
    ultrafeedback: %{
      repo_id: "argilla/ultrafeedback-binarized-preferences",
      parser: :ultrafeedback,
      description: "UltraFeedback binarized preference dataset"
    },
    arena_140k: %{
      repo_id: "lmarena-ai/arena-human-preference-140k",
      parser: :arena,
      description: "LMArena Arena Human Preference 140K dataset"
    },
    tulu3_preference: %{
      repo_id: "allenai/llama-3.1-tulu-3-8b-preference-mixture",
      parser: :tulu_preference,
      description: "Tulu 3.8B Preference Mixture"
    }
  }

  @doc """
  Load a preference/comparison dataset.

  ## Arguments
    * `dataset_name` - One of the supported dataset names (see module docs)
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

  defp load_from_huggingface(dataset_name, dataset_info, opts) do
    %{repo_id: repo_id, parser: parser} = dataset_info
    config = Map.get(dataset_info, :config)
    split = Keyword.get(opts, :split, "train") |> to_string()
    sample_size = Keyword.get(opts, :sample_size)
    token = Keyword.get(opts, :token)

    fetch_opts = [split: split, token: token]
    fetch_opts = if config, do: Keyword.put(fetch_opts, :config, config), else: fetch_opts

    case HuggingFace.fetch(repo_id, fetch_opts) do
      {:ok, raw_data} ->
        items = parse_preference_data(raw_data, parser)

        items = if sample_size, do: Enum.take(items, sample_size), else: items

        dataset =
          Dataset.new(
            to_string(dataset_name),
            "1.0",
            items,
            %{
              source: "huggingface:#{repo_id}",
              split: split,
              license: "mit",
              domain: "preference"
            }
          )

        {:ok, dataset}

      {:error, reason} ->
        {:error, {:huggingface_fetch_failed, reason}}
    end
  end

  defp parse_preference_data(raw_data, parser) do
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

  # All parse_item/3 clauses grouped together

  defp parse_item(item, :hh_rlhf, idx) do
    with {:ok, comparison} <- Comparison.from_hh_rlhf(item) do
      label = LabeledComparison.from_hh_rlhf()

      {:ok,
       %{
         id: "hh_rlhf_#{idx}",
         input: %{
           comparison: comparison
         },
         expected: label,
         metadata: %{
           source: "hh-rlhf"
         }
       }}
    end
  end

  defp parse_item(item, :helpsteer, idx) do
    # HelpSteer3 uses context, response1, response2, overall_preference
    context = item["context"] || []
    response1 = item["response1"] || ""
    response2 = item["response2"] || ""
    preference = item["overall_preference"]

    # Skip ties (overall_preference == 0)
    if preference == 0 do
      {:error, :tie}
    else
      # Extract prompt from context (first user message)
      prompt = extract_helpsteer_prompt(context)
      comparison = Comparison.new(prompt, response1, response2, %{source: :helpsteer3})

      # overall_preference < 0 means response1 is better (A)
      # overall_preference > 0 means response2 is better (B)
      label =
        if is_number(preference) and preference < 0 do
          LabeledComparison.new(:a)
        else
          LabeledComparison.new(:b)
        end

      {:ok,
       %{
         id: "helpsteer_#{idx}",
         input: %{
           comparison: comparison
         },
         expected: label,
         metadata: %{
           source: "helpsteer3",
           overall_preference: preference
         }
       }}
    end
  end

  defp parse_item(item, :helpsteer2, idx) do
    # HelpSteer2 has a different format - single response with scores
    prompt = item["prompt"]
    response = item["response"]
    score = item["helpfulness"] || item["correctness"] || 3.0

    comparison = Comparison.new(prompt, response, "", %{score: score})

    {:ok,
     %{
       id: "helpsteer2_#{idx}",
       input: %{
         comparison: comparison
       },
       expected: nil,
       metadata: %{
         source: "helpsteer2",
         helpfulness: item["helpfulness"],
         correctness: item["correctness"],
         coherence: item["coherence"],
         complexity: item["complexity"],
         verbosity: item["verbosity"]
       }
     }}
  end

  defp parse_item(item, :ultrafeedback, idx) do
    # UltraFeedback (argilla/ultrafeedback-binarized-preferences) format
    instruction = item["instruction"] || item["prompt"] || ""
    chosen_response = item["chosen_response"] || ""
    rejected_response = item["rejected_response"] || ""

    comparison =
      Comparison.new(instruction, chosen_response, rejected_response, %{source: :ultrafeedback})

    # In binarized format, chosen is always better (A)
    label = LabeledComparison.new(:a)

    {:ok,
     %{
       id: "ultrafeedback_#{idx}",
       input: %{
         comparison: comparison
       },
       expected: label,
       metadata: %{
         source: "ultrafeedback",
         chosen_model: item["chosen_model"],
         rejected_model: item["rejected_model"]
       }
     }}
  end

  defp parse_item(item, :arena, idx) do
    # Arena format uses conversation_a and conversation_b (full conversations)
    winner = item["winner"]
    conversation_a = item["conversation_a"] || []
    conversation_b = item["conversation_b"] || []

    # Skip ties or invalid winners
    if winner in ["model_a", "model_b"] do
      # Extract prompt from first user message in conversation_a
      prompt = extract_arena_prompt(conversation_a)

      comparison = Comparison.new(prompt, conversation_a, conversation_b, %{source: :arena})

      label =
        case winner do
          "model_a" -> LabeledComparison.new(:a)
          "model_b" -> LabeledComparison.new(:b)
        end

      {:ok,
       %{
         id: "arena_#{idx}",
         input: %{
           comparison: comparison
         },
         expected: label,
         metadata: %{
           source: "arena",
           model_a: item["model_a"],
           model_b: item["model_b"]
         }
       }}
    else
      {:error, :invalid_winner}
    end
  end

  defp parse_item(item, :tulu_preference, idx) do
    # Tulu preference: has chosen and rejected conversations
    chosen = item["chosen"] || []
    rejected = item["rejected"] || []

    # Try to extract prompts
    prompt =
      case chosen do
        [%{"role" => "user", "content" => content} | _] -> content
        _ -> item["prompt"] || ""
      end

    comparison = Comparison.new(prompt, chosen, rejected, %{source: :tulu_preference})
    label = LabeledComparison.new(:a)

    {:ok,
     %{
       id: "tulu_pref_#{idx}",
       input: %{
         comparison: comparison
       },
       expected: label,
       metadata: %{
         source: "tulu_preference"
       }
     }}
  end

  # Helper functions for parsing

  defp extract_helpsteer_prompt(context) when is_list(context) do
    # Context is a conversation list, find first user message
    context
    |> Enum.find(fn msg -> msg["role"] == "user" end)
    |> case do
      nil -> ""
      msg -> msg["content"] || ""
    end
  end

  defp extract_helpsteer_prompt(_), do: ""

  defp extract_arena_prompt(conversation) when is_list(conversation) do
    # Find first user message content
    conversation
    |> Enum.find(fn msg -> msg["role"] == "user" end)
    |> case do
      nil -> ""
      msg -> extract_content_text(msg["content"])
    end
  end

  defp extract_arena_prompt(_), do: ""

  defp extract_content_text(content) when is_binary(content), do: content

  defp extract_content_text(content) when is_list(content) do
    # Arena uses {"type": "text", "text": "..."} format
    content
    |> Enum.filter(fn item -> is_map(item) and item["type"] == "text" end)
    |> Enum.map_join(" ", fn item -> item["text"] || "" end)
  end

  defp extract_content_text(_), do: ""

  @doc """
  List available preference datasets.
  """
  @spec available_datasets() :: [atom()]
  def available_datasets, do: Map.keys(@datasets)
end
