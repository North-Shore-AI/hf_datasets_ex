# examples/streaming_example.exs
# Run with: mix run examples/streaming_example.exs
#
# Demonstrates streaming with IterableDataset.

require Logger

alias HfDatasetsEx.IterableDataset

Logger.info("=== Streaming Example ===\n")

repo_id = "openai/gsm8k"
opts = [split: "train", streaming: true]

case HfDatasetsEx.load_dataset(repo_id, opts) do
  {:ok, %IterableDataset{} = iterable} ->
    IO.puts("Streaming #{iterable.name} (split=train)")

    items = IterableDataset.take(iterable, 3)

    Enum.with_index(items, 1)
    |> Enum.each(fn {item, idx} ->
      question =
        item["question"] ||
          item[:question] ||
          get_in(item, [:input, :question]) ||
          get_in(item, ["input", "question"])

      IO.puts("\nSample #{idx}")
      id = item["id"] || item[:id] || "n/a"
      IO.puts("ID: #{id}")
      IO.puts("Question: #{String.slice(to_string(question), 0, 80)}...")
    end)

  {:error, reason} ->
    IO.puts("Failed to stream dataset: #{inspect(reason)}")
    IO.puts("If this repo is gated, set HF_TOKEN and retry.")
end
