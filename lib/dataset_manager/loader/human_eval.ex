defmodule HfDatasetsEx.Loader.HumanEval do
  @moduledoc """
  HumanEval code generation benchmark loader.

  HumanEval contains 164 programming problems with function signatures and test cases.
  Used to evaluate code generation capabilities.

  ## HuggingFace Dataset

  The official HumanEval dataset is hosted at `openai/openai_humaneval` on HuggingFace.

  ## Example

      {:ok, dataset} = HfDatasetsEx.Loader.HumanEval.load()
      {:ok, dataset} = HfDatasetsEx.Loader.HumanEval.load(sample_size: 50)

  """

  alias HfDatasetsEx.{Dataset, Source, Format}

  @repo_id "openai/openai_humaneval"

  @doc """
  Load HumanEval dataset from HuggingFace.

  ## Options

    * `:sample_size` - Limit number of items. Default: all (164)

  ## Examples

      {:ok, dataset} = HumanEval.load()
      {:ok, dataset} = HumanEval.load(sample_size: 50)

  """
  @spec load(keyword()) :: {:ok, Dataset.t()} | {:error, term()}
  def load(opts \\ []) do
    load_from_huggingface(opts)
  end

  # Load from HuggingFace
  defp load_from_huggingface(opts) do
    sample_size = Keyword.get(opts, :sample_size)

    # HumanEval on HuggingFace is stored as parquet
    file_path = "openai_humaneval/test-00000-of-00001.parquet"

    case Source.HuggingFace.download(@repo_id, file_path, []) do
      {:ok, local_path} ->
        case parse_humaneval_parquet(local_path, sample_size) do
          {:ok, _} = success -> success
          {:error, reason} -> {:error, {:parse_failed, reason}}
        end

      {:error, _reason} ->
        # Try alternative path
        case Source.HuggingFace.download(@repo_id, "data/test-00000-of-00001.parquet", []) do
          {:ok, local_path} ->
            case parse_humaneval_parquet(local_path, sample_size) do
              {:ok, _} = success ->
                success

              {:error, reason} ->
                {:error, {:parse_failed, reason}}
            end

          {:error, reason} ->
            {:error, {:huggingface_download_failed, reason}}
        end
    end
  end

  defp parse_humaneval_parquet(path, sample_size) do
    case Format.Parquet.parse(path) do
      {:ok, rows} ->
        items =
          rows
          |> Enum.with_index()
          |> Enum.map(fn {row, idx} ->
            task_id = row["task_id"] || row[:task_id] || "HumanEval/#{idx}"
            prompt = row["prompt"] || row[:prompt]
            canonical = row["canonical_solution"] || row[:canonical_solution]
            test_code = row["test"] || row[:test]
            entry_point = row["entry_point"] || row[:entry_point]

            %{
              id: "humaneval_#{idx}",
              input: %{
                signature: prompt,
                tests: test_code,
                entry_point: entry_point,
                description: extract_description(prompt)
              },
              expected: canonical,
              metadata: %{
                task_id: task_id,
                difficulty: estimate_difficulty(canonical)
              }
            }
          end)

        final_items = if sample_size, do: Enum.take(items, sample_size), else: items

        dataset =
          Dataset.new(
            "humaneval",
            "1.0",
            final_items,
            %{
              source: "huggingface:#{@repo_id}",
              license: "MIT",
              domain: "code_generation",
              language: "python"
            }
          )

        {:ok, dataset}

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  @doc """
  Parse HumanEval JSONL format.
  """
  def parse_jsonl(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.with_index()
    |> Enum.map(fn {line, idx} ->
      case Jason.decode(line) do
        {:ok, item} ->
          %{
            id: "humaneval_#{idx}",
            input: %{
              signature: item["prompt"],
              tests: item["test"],
              entry_point: item["entry_point"],
              description: item["prompt"] |> extract_description()
            },
            expected: item["canonical_solution"],
            metadata: %{
              task_id: item["task_id"],
              difficulty: estimate_difficulty(item["canonical_solution"])
            }
          }

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_description(nil), do: ""

  defp extract_description(prompt) do
    # Extract docstring from prompt
    prompt
    |> String.split("\n")
    |> Enum.find("", &String.contains?(&1, "\"\"\""))
    |> String.trim()
  end

  defp estimate_difficulty(nil), do: "medium"

  defp estimate_difficulty(solution) do
    # Simple heuristic: longer solutions are harder
    solution_length = String.length(solution)

    cond do
      solution_length < 100 -> "easy"
      solution_length < 300 -> "medium"
      true -> "hard"
    end
  end
end
