# K-Fold Cross-Validation Example
#
# This example demonstrates k-fold cross-validation splits
# for organizing data for robust model training and evaluation.
#
# Run this file with: mix run examples/cross_validation.exs

require Logger

Logger.info("=== K-Fold Cross-Validation Example ===\n")

# Load dataset
Logger.info("Loading MMLU STEM dataset...")
{:ok, dataset} = HfDatasetsEx.load(:mmlu_stem, sample_size: 100)
IO.puts("Loaded #{length(dataset.items)} items\n")

# Create k-fold splits
k = 5
Logger.info("Creating #{k}-fold cross-validation splits...")

{:ok, folds} = HfDatasetsEx.k_fold(dataset, k: k, shuffle: true, seed: 42)
IO.puts("Created #{length(folds)} folds\n")

# Verify fold sizes
Logger.info("Verifying fold sizes...")
IO.puts("\nFold Sizes:")

Enum.each(folds, fn {train, test} ->
  train_size = length(train.items)
  test_size = length(test.items)
  total = train_size + test_size

  IO.puts("  Train: #{train_size}, Test: #{test_size}, Total: #{total}")
end)

# Demonstrate no overlap between test sets
Logger.info("\nVerifying no overlap between test sets...")

all_test_ids =
  folds
  |> Enum.flat_map(fn {_train, test} -> Enum.map(test.items, & &1.id) end)

unique_test_ids = Enum.uniq(all_test_ids)

IO.puts("Total test items across folds: #{length(all_test_ids)}")
IO.puts("Unique test items: #{length(unique_test_ids)}")
IO.puts("No duplicates: #{length(all_test_ids) == length(unique_test_ids)}")

# Show subject distribution in each fold
Logger.info("\nSubject distribution in test sets:")

folds
|> Enum.with_index()
|> Enum.each(fn {{_train, test}, fold_idx} ->
  subjects = Enum.frequencies_by(test.items, & &1.metadata.subject)
  IO.puts("  Fold #{fold_idx}: #{inspect(Map.keys(subjects))}")
end)

# Demonstrate how to use folds for training/testing
Logger.info("\nFolds ready for cross-validation training loop:")

Enum.with_index(folds, fn {train_fold, test_fold}, fold_idx ->
  IO.puts("  Fold #{fold_idx}:")
  IO.puts("    Train set: #{length(train_fold.items)} items for model training")
  IO.puts("    Test set: #{length(test_fold.items)} items for model evaluation")
end)

IO.puts("")

# Different k values
Logger.info("Comparing different k values:")

for k_val <- [3, 5, 10] do
  {:ok, k_folds} = HfDatasetsEx.k_fold(dataset, k: k_val, shuffle: true, seed: 42)
  {train, test} = hd(k_folds)
  train_pct = length(train.items) / length(dataset.items) * 100
  test_pct = length(test.items) / length(dataset.items) * 100
  IO.puts("  k=#{k_val}: train=#{Float.round(train_pct, 1)}%, test=#{Float.round(test_pct, 1)}%")
end

Logger.info("\n=== Cross-Validation Example Completed ===")
