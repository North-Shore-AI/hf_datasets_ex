# examples/load_dataset_example.exs
# Run with: mix run examples/load_dataset_example.exs
#
# Demonstrates the HuggingFace-style load_dataset API.

require Logger

Logger.info("=== load_dataset Example ===\n")

repo_id = "openai/gsm8k"
opts = [config: "main", split: "train"]

case HfDatasetsEx.load_dataset(repo_id, opts) do
  {:ok, dataset} ->
    IO.puts(
      "Loaded #{dataset.name} (split=#{dataset.metadata.split}, config=#{dataset.metadata.config})"
    )

    IO.puts("Total items: #{length(dataset.items)}")

    dataset.items
    |> Enum.take(3)
    |> Enum.with_index(1)
    |> Enum.each(fn {item, idx} ->
      question = get_in(item, [:input, :question]) || get_in(item, ["input", "question"])
      question = question || item["question"] || item[:question]
      answer = item["answer"] || item[:answer] || item["expected"] || item[:expected] || "n/a"
      id = item["id"] || item[:id] || "n/a"
      IO.puts("\nSample #{idx}")
      IO.puts("ID: #{id}")
      IO.puts("Question: #{String.slice(to_string(question), 0, 80)}...")
      IO.puts("Answer: #{inspect(answer)}")
    end)

  {:error, reason} ->
    IO.puts("Failed to load dataset: #{inspect(reason)}")
    IO.puts("If this repo is gated, set HF_TOKEN and retry.")
end
