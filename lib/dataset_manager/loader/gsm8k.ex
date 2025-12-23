defmodule HfDatasetsEx.Loader.GSM8K do
  @moduledoc """
  GSM8K (Grade School Math 8K) dataset loader.

  Contains 8,500 grade school math word problems with natural language solutions.

  ## Examples

      # Load train split from HuggingFace
      {:ok, dataset} = HfDatasetsEx.Loader.GSM8K.load(split: :train)

      # Load test split
      {:ok, dataset} = HfDatasetsEx.Loader.GSM8K.load(split: :test)

  """

  alias HfDatasetsEx.Dataset
  alias HfDatasetsEx.Fetcher.HuggingFace

  @repo_id "openai/gsm8k"
  @default_config "main"

  @doc """
  Load GSM8K dataset.

  ## Options
    * `:split` - Dataset split (:train or :test, default: :train)
    * `:sample_size` - Limit number of items (default: all)
    * `:config` - Dataset config (default: "main", can also be "socratic")
    * `:token` - HuggingFace API token

  """
  def load(opts \\ []) do
    load_from_huggingface(opts)
  end

  defp load_from_huggingface(opts) do
    split = Keyword.get(opts, :split, :train) |> to_string()
    config = Keyword.get(opts, :config, @default_config)
    sample_size = Keyword.get(opts, :sample_size)
    token = Keyword.get(opts, :token)

    case HuggingFace.fetch(@repo_id, split: split, config: config, token: token) do
      {:ok, raw_data} ->
        items = parse_huggingface_data(raw_data)

        items = if sample_size, do: Enum.take(items, sample_size), else: items

        dataset =
          Dataset.new(
            "gsm8k",
            "1.0",
            items,
            %{
              source: "huggingface:#{@repo_id}",
              split: split,
              config: config,
              license: "MIT",
              domain: "math_word_problems"
            }
          )

        {:ok, dataset}

      {:error, reason} ->
        {:error, {:huggingface_fetch_failed, reason}}
    end
  end

  defp parse_huggingface_data(raw_data) do
    raw_data
    |> Enum.with_index()
    |> Enum.map(fn {item, idx} ->
      answer_text = item["answer"] || ""

      %{
        id: "gsm8k_#{idx}",
        input: %{
          question: item["question"]
        },
        expected: %{
          answer: extract_numerical_answer(answer_text),
          reasoning: answer_text
        },
        metadata: %{
          complexity: count_steps(answer_text),
          difficulty: estimate_difficulty(answer_text)
        }
      }
    end)
  end

  @doc """
  Parse GSM8K JSONL format.
  """
  def parse_jsonl(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.with_index()
    |> Enum.map(fn {line, idx} ->
      case Jason.decode(line) do
        {:ok, item} ->
          %{
            id: "gsm8k_#{idx}",
            input: item["question"],
            expected: %{
              answer: extract_numerical_answer(item["answer"]),
              reasoning: item["answer"]
            },
            metadata: %{
              complexity: count_steps(item["answer"]),
              difficulty: estimate_difficulty(item["answer"])
            }
          }

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Extract final numerical answer from GSM8K answer format.

  GSM8K answers end with "#### <number>"

  ## Examples

      iex> extract_numerical_answer("The answer is #### 42")
      42.0

      iex> extract_numerical_answer("#### 1,234.56")
      1234.56

      iex> extract_numerical_answer("no answer here")
      nil

  """
  def extract_numerical_answer(nil), do: nil

  def extract_numerical_answer(answer_text) when is_binary(answer_text) do
    case String.split(answer_text, "####") do
      [_] ->
        nil

      parts ->
        parts
        |> List.last()
        |> String.trim()
        |> String.replace(",", "")
        |> String.replace("$", "")
        |> parse_number()
    end
  end

  defp parse_number(str) do
    str = String.trim(str)

    cond do
      String.contains?(str, ".") ->
        case Float.parse(str) do
          {num, _} -> num
          :error -> nil
        end

      true ->
        case Integer.parse(str) do
          {num, _} -> num * 1.0
          :error -> nil
        end
    end
  end

  defp count_steps(answer_text) do
    # Count number of calculation steps (approximation)
    answer_text
    |> String.split("<<")
    |> length()
  end

  defp estimate_difficulty(answer_text) do
    steps = count_steps(answer_text)

    cond do
      steps <= 2 -> "easy"
      steps <= 4 -> "medium"
      true -> "hard"
    end
  end
end
