# Basic Usage Examples for HfDatasetsEx
#
# Run this file with: mix run examples/basic_usage.exs

require Logger

Logger.info("=== HfDatasetsEx Basic Usage Examples ===\n")

# Example 1: Load a dataset
Logger.info("Example 1: Loading MMLU STEM dataset")
{:ok, dataset} = HfDatasetsEx.load(:mmlu_stem, sample_size: 20)

IO.puts("Dataset: #{dataset.name}")
IO.puts("Version: #{dataset.version}")
IO.puts("Items: #{length(dataset.items)}")
IO.puts("Domain: #{dataset.metadata.domain}")
IO.puts("First item: #{inspect(Enum.at(dataset.items, 0))}\n")

# Example 2: Random sampling
Logger.info("Example 2: Random sampling")
{:ok, large_dataset} = HfDatasetsEx.load(:mmlu_stem, sample_size: 100)

{:ok, sample} = HfDatasetsEx.random_sample(large_dataset, size: 20, seed: 42)

IO.puts("Original size: #{length(large_dataset.items)}")
IO.puts("Sample size: #{length(sample.items)}")
IO.puts("Sample method: #{sample.metadata.sample_method}\n")

# Example 3: Stratified sampling
Logger.info("Example 3: Stratified sampling")

{:ok, stratified} =
  HfDatasetsEx.stratified_sample(large_dataset,
    size: 30,
    strata_field: [:metadata, :subject]
  )

IO.puts("Stratified sample size: #{length(stratified.items)}")
IO.puts("Stratification field: #{inspect(stratified.metadata.strata_field)}")

# Show distribution
subjects = Enum.frequencies_by(stratified.items, & &1.metadata.subject)
IO.puts("Subject distribution:")

Enum.each(subjects, fn {subject, count} ->
  IO.puts("  #{subject}: #{count}")
end)

IO.puts("")

# Example 4: Train/test split
Logger.info("Example 4: Train/test split")

{:ok, {train, test}} =
  HfDatasetsEx.train_test_split(large_dataset, test_size: 0.2, shuffle: true)

IO.puts("Total items: #{length(large_dataset.items)}")
IO.puts("Train items: #{length(train.items)}")
IO.puts("Test items: #{length(test.items)}")

train_ratio = length(train.items) / length(large_dataset.items)
IO.puts("Train ratio: #{Float.round(train_ratio * 100, 2)}%\n")

# Example 5: K-fold cross-validation splits
Logger.info("Example 5: K-fold cross-validation splits")

{:ok, folds} = HfDatasetsEx.k_fold(large_dataset, k: 5)

IO.puts("Number of folds: #{length(folds)}")

Enum.with_index(folds, fn {train_fold, test_fold}, idx ->
  IO.puts("  Fold #{idx}: train=#{length(train_fold.items)}, test=#{length(test_fold.items)}")
end)

IO.puts("")

# Example 6: Cache management
Logger.info("Example 6: Cache management")

cached = HfDatasetsEx.list_cached()
IO.puts("Cached datasets: #{length(cached)}")

if length(cached) > 0 do
  IO.puts("Cached items:")

  Enum.each(cached, fn item ->
    IO.puts("  - #{item["name"]} (v#{item["version"]})")
  end)
end

Logger.info("\n=== Examples completed successfully! ===")
