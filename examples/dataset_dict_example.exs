# examples/dataset_dict_example.exs
# Run with: mix run examples/dataset_dict_example.exs
#
# Demonstrates DatasetDict when loading all splits.

require Logger

alias HfDatasetsEx.{DatasetDict, Dataset}

Logger.info("=== DatasetDict Example ===\n")

repo_id = "openai/gsm8k"

case HfDatasetsEx.load_dataset(repo_id) do
  {:ok, %DatasetDict{} = dataset_dict} ->
    splits = DatasetDict.split_names(dataset_dict) |> Enum.sort()
    IO.puts("Loaded #{length(splits)} splits: #{Enum.join(splits, ", ")}")
    IO.puts("Row counts: #{inspect(DatasetDict.num_rows(dataset_dict))}")
    IO.puts("Column names: #{inspect(DatasetDict.column_names(dataset_dict))}")

    train = dataset_dict["train"]
    IO.puts("\nTrain split sample (#{Dataset.num_items(train)} rows):")
    IO.puts(inspect(Enum.take(train.items, 2), limit: 2))

  {:ok, other} ->
    IO.puts("Expected DatasetDict, got: #{inspect(other)}")

  {:error, reason} ->
    IO.puts("Failed to load dataset: #{inspect(reason)}")
    IO.puts("If this repo is gated, set HF_TOKEN and retry.")
end
