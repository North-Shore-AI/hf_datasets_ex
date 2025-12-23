# examples/math/gsm8k_example.exs
# Run with: mix run examples/math/gsm8k_example.exs
#
# This example demonstrates loading the GSM8K dataset from HuggingFace
# and performing common operations.

alias HfDatasetsEx.Loader.GSM8K
alias HfDatasetsEx.Sampler

IO.puts("=" <> String.duplicate("=", 60))
IO.puts("GSM8K Dataset Example")
IO.puts("=" <> String.duplicate("=", 60))
IO.puts("")

# Load the test split (smaller, faster)
IO.puts("Loading GSM8K test split from HuggingFace...")
{:ok, dataset} = GSM8K.load(split: :test)

IO.puts("Total items: #{length(dataset.items)}")
IO.puts("Dataset name: #{dataset.name}")
IO.puts("Source: #{dataset.metadata.source}")
IO.puts("")

# Show first 3 examples
IO.puts("-" <> String.duplicate("-", 60))
IO.puts("Sample Problems")
IO.puts("-" <> String.duplicate("-", 60))
IO.puts("")

dataset.items
|> Enum.take(3)
|> Enum.each(fn item ->
  question =
    case item.input do
      %{} = input_map -> input_map[:question] || input_map["question"]
      other -> other
    end

  IO.puts("ID: #{item.id}")
  IO.puts("Question: #{String.slice(to_string(question), 0, 100)}...")
  IO.puts("Expected Answer: #{item.expected.answer}")
  IO.puts("Difficulty: #{item.metadata.difficulty}")
  IO.puts("")
end)

# Demonstrate sampling
IO.puts("-" <> String.duplicate("-", 60))
IO.puts("Sampling Demo")
IO.puts("-" <> String.duplicate("-", 60))
IO.puts("")

# Shuffle with a fixed seed for reproducibility
{:ok, shuffled} = Sampler.shuffle(dataset, seed: 42)
IO.puts("Shuffled dataset (seed=42)")
IO.puts("First item after shuffle: #{hd(shuffled.items).id}")
IO.puts("")

# Take first 50 items
{:ok, subset} = Sampler.take(dataset, 50)
IO.puts("Subset of 50 items: #{length(subset.items)} items")
IO.puts("")

# Train/test split
{:ok, {train, test}} = Sampler.train_test_split(dataset, test_size: 0.2, seed: 42)
IO.puts("Train/Test split:")
IO.puts("  Train size: #{length(train.items)}")
IO.puts("  Test size: #{length(test.items)}")
IO.puts("")

# Filter by difficulty
{:ok, hard_problems} =
  Sampler.filter(dataset, fn item ->
    item.metadata.difficulty == "hard"
  end)

IO.puts("Hard problems only: #{length(hard_problems.items)} items")
IO.puts("")

IO.puts("=" <> String.duplicate("=", 60))
IO.puts("Example complete!")
IO.puts("=" <> String.duplicate("=", 60))
