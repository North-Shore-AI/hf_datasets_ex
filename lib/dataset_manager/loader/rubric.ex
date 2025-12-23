defmodule HfDatasetsEx.Loader.Rubric do
  @moduledoc """
  Loader for rubric-based evaluation datasets.

  Supports:
    - Feedback-Collection (prometheus-eval/Feedback-Collection)

  These datasets contain instructions with scoring rubrics for training
  evaluator/grader models.

  ## Examples

      # Load Feedback-Collection
      {:ok, dataset} = HfDatasetsEx.Loader.Rubric.load(:feedback_collection)

      # Load with sample size
      {:ok, dataset} = HfDatasetsEx.Loader.Rubric.load(:feedback_collection, sample_size: 500)

  """

  alias HfDatasetsEx.Dataset
  alias HfDatasetsEx.Fetcher.HuggingFace

  @datasets %{
    feedback_collection: %{
      repo_id: "prometheus-eval/Feedback-Collection",
      description: "Prometheus Feedback Collection for rubric-based evaluation"
    }
  }

  @doc """
  Load a rubric-based evaluation dataset.

  ## Arguments
    * `dataset_name` - Currently only `:feedback_collection`
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

    # Feedback-Collection uses a single JSON file, not standard train/test splits
    # Download the specific file directly
    file_path = "new_feedback_collection.json"

    case HuggingFace.download_file(repo_id, file_path, token: token) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, raw_data} when is_list(raw_data) ->
            items = parse_rubric_data(raw_data)
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
                  domain: "rubric_evaluation"
                }
              )

            {:ok, dataset}

          {:ok, _} ->
            {:error, {:parse_error, :expected_array}}

          {:error, reason} ->
            {:error, {:json_parse_error, reason}}
        end

      {:error, reason} ->
        {:error, {:huggingface_fetch_failed, reason}}
    end
  end

  defp parse_rubric_data(raw_data) do
    raw_data
    |> Enum.with_index()
    |> Enum.map(fn {item, idx} ->
      parse_feedback_item(item, idx)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_feedback_item(item, idx) do
    instruction = item["orig_instruction"] || item["instruction"] || ""
    criteria = item["orig_criteria"] || item["criteria"] || ""
    reference = item["orig_reference_answer"] || item["reference_answer"] || ""

    # Build rubric from score descriptions
    rubric = build_rubric(item)

    %{
      id: "feedback_#{idx}",
      input: %{
        instruction: instruction,
        criteria: criteria
      },
      expected: %{
        reference_answer: reference,
        rubric: rubric
      },
      metadata: %{
        source: "feedback_collection",
        has_rubric: map_size(rubric) > 0
      }
    }
  end

  defp build_rubric(item) do
    # Feedback-Collection has score1_description through score5_description
    1..5
    |> Enum.reduce(%{}, fn i, acc ->
      key = "orig_score#{i}_description"
      alt_key = "score#{i}_description"

      case item[key] || item[alt_key] do
        nil -> acc
        description -> Map.put(acc, i, description)
      end
    end)
  end

  @doc """
  List available rubric datasets.
  """
  @spec available_datasets() :: [atom()]
  def available_datasets, do: Map.keys(@datasets)
end
