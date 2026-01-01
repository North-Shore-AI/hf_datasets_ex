# HuggingFace Hub Push Example
# Demonstrates uploading datasets to HuggingFace Hub

alias HfDatasetsEx.{Dataset, DatasetDict}

IO.puts("=== HuggingFace Hub Push Example ===\n")

# Check for token
token = System.get_env("HF_TOKEN") || System.get_env("HF_HUB_TOKEN")

if is_nil(token) or token == "" do
  IO.puts("""
  ⚠️  No HF_TOKEN found in environment.

  To run this example, set your HuggingFace token:
    export HF_TOKEN=hf_your_token_here

  Get a token at: https://huggingface.co/settings/tokens

  Showing what WOULD happen with a real token...
  """)

  # Demo without actually pushing
  dataset =
    Dataset.from_list([
      %{"text" => "Hello world", "label" => "positive"},
      %{"text" => "This is bad", "label" => "negative"}
    ])

  IO.puts("Created dataset with #{Dataset.num_items(dataset)} items")
  IO.puts("Columns: #{inspect(Dataset.column_names(dataset))}")
  IO.puts("\nTo push this dataset, you would call:")
  IO.puts(~s|  Dataset.push_to_hub(dataset, "your-username/my-dataset")|)
  IO.puts("\nWith options:")
  IO.puts(~s|  Dataset.push_to_hub(dataset, "your-username/my-dataset",|)
  IO.puts(~s|    private: true,|)
  IO.puts(~s|    split: "train",|)
  IO.puts(~s|    commit_message: "Add training data"|)
  IO.puts(~s|  )|)
else
  IO.puts("✓ Found HF_TOKEN\n")

  # Create a test dataset
  dataset =
    Dataset.from_list([
      %{"text" => "Example text 1", "label" => 0},
      %{"text" => "Example text 2", "label" => 1},
      %{"text" => "Example text 3", "label" => 0}
    ])

  IO.puts("Created dataset with #{Dataset.num_items(dataset)} items")

  # Generate a unique repo name for testing
  timestamp = DateTime.utc_now() |> DateTime.to_unix()
  repo_id = "hf-datasets-ex-test/example-#{timestamp}"

  IO.puts("\nPushing to: #{repo_id}")
  IO.puts("(This will create a new dataset repository)\n")

  case Dataset.push_to_hub(dataset, repo_id, token: token, private: true) do
    {:ok, url} ->
      IO.puts("✓ Successfully pushed!")
      IO.puts("  URL: #{url}")
      IO.puts("\nNote: Delete this test repo when done:")
      IO.puts("  https://huggingface.co/datasets/#{repo_id}/settings")

    {:error, reason} ->
      IO.puts("✗ Push failed: #{inspect(reason)}")
  end

  # DatasetDict example
  IO.puts("\n=== DatasetDict Push ===")
  IO.puts("You can also push multiple splits at once:")
  IO.puts(~s|  dd = DatasetDict.new(%{|)
  IO.puts(~s|    "train" => train_dataset,|)
  IO.puts(~s|    "test" => test_dataset|)
  IO.puts(~s|  })|)
  IO.puts(~s|  DatasetDict.push_to_hub(dd, "username/my-dataset")|)
end

IO.puts("\n=== Hub Push Example Complete ===")
