# Sampling Strategies Example
#
# This example demonstrates different sampling strategies and when to use them:
# - Random sampling for quick prototyping
# - Stratified sampling for balanced evaluation
# - Train/test splitting for model development
#
# Run this file with: mix run examples/sampling_strategies.exs

require Logger

Logger.info("=== Sampling Strategies Example ===\n")

# Load a larger dataset
Logger.info("Loading full MMLU STEM dataset...")
{:ok, full_dataset} = HfDatasetsEx.load(:mmlu_stem, sample_size: 200)
IO.puts("Full dataset size: #{length(full_dataset.items)} items\n")

# Analyze original distribution
original_distribution =
  full_dataset.items
  |> Enum.frequencies_by(& &1.metadata.subject)
  |> Enum.sort()

IO.puts("Original Subject Distribution:")

Enum.each(original_distribution, fn {subject, count} ->
  percentage = count / length(full_dataset.items) * 100
  IO.puts("  #{subject}: #{count} (#{Float.round(percentage, 1)}%)")
end)

IO.puts("")

# Strategy 1: Random Sampling
Logger.info("Strategy 1: Random Sampling")
IO.puts("Use case: Quick prototyping, initial testing, when class balance doesn't matter\n")

{:ok, random_sample} = HfDatasetsEx.random_sample(full_dataset, size: 50, seed: 42)

random_distribution =
  random_sample.items
  |> Enum.frequencies_by(& &1.metadata.subject)
  |> Enum.sort()

IO.puts("Random Sample (n=50):")
IO.puts("  Total items: #{length(random_sample.items)}")
IO.puts("  Unique subjects: #{length(random_distribution)}")
IO.puts("")

# Strategy 2: Stratified Sampling
Logger.info("Strategy 2: Stratified Sampling")
IO.puts("Use case: Maintaining class balance, fair evaluation across categories\n")

{:ok, stratified_sample} =
  HfDatasetsEx.stratified_sample(
    full_dataset,
    size: 50,
    strata_field: [:metadata, :subject]
  )

stratified_distribution =
  stratified_sample.items
  |> Enum.frequencies_by(& &1.metadata.subject)
  |> Enum.sort()

IO.puts("Stratified Sample (n=50):")
IO.puts("  Total items: #{length(stratified_sample.items)}")
IO.puts("  Unique subjects: #{length(stratified_distribution)}")
IO.puts("\n  Subject Distribution:")

Enum.each(stratified_distribution, fn {subject, count} ->
  original_count = Map.get(Enum.into(original_distribution, %{}), subject, 0)
  original_pct = original_count / length(full_dataset.items) * 100
  sample_pct = count / length(stratified_sample.items) * 100

  IO.puts("    #{subject}:")
  IO.puts("      Original: #{Float.round(original_pct, 1)}%")
  IO.puts("      Sample: #{Float.round(sample_pct, 1)}%")
end)

IO.puts("")

# Strategy 3: Train/Test Split
Logger.info("Strategy 3: Train/Test Split")
IO.puts("Use case: Model development, performance evaluation\n")

{:ok, {train, test}} =
  HfDatasetsEx.train_test_split(
    full_dataset,
    test_size: 0.2,
    shuffle: true,
    seed: 42
  )

IO.puts("Train/Test Split (80/20):")
IO.puts("  Train size: #{length(train.items)}")
IO.puts("  Test size: #{length(test.items)}")
IO.puts("  Total: #{length(train.items) + length(test.items)}")
IO.puts("")

# Verify no overlap between train and test
train_ids = MapSet.new(train.items, & &1.id)
test_ids = MapSet.new(test.items, & &1.id)
overlap = MapSet.intersection(train_ids, test_ids)

IO.puts("  Data leak check:")
IO.puts("    Overlap: #{MapSet.size(overlap)} items")

IO.puts(
  "    Status: #{if MapSet.size(overlap) == 0, do: "✓ No data leakage", else: "✗ Data leakage detected!"}"
)

IO.puts("")

# Strategy 4: Reproducibility Test
Logger.info("Strategy 4: Reproducibility with Seeds")
IO.puts("Demonstrating reproducible sampling with fixed seeds\n")

# Create two samples with same seed
{:ok, sample1} = HfDatasetsEx.random_sample(full_dataset, size: 30, seed: 12345)
{:ok, sample2} = HfDatasetsEx.random_sample(full_dataset, size: 30, seed: 12345)

# Create sample with different seed
{:ok, sample3} = HfDatasetsEx.random_sample(full_dataset, size: 30, seed: 67890)

sample1_ids = Enum.map(sample1.items, & &1.id) |> Enum.sort()
sample2_ids = Enum.map(sample2.items, & &1.id) |> Enum.sort()
sample3_ids = Enum.map(sample3.items, & &1.id) |> Enum.sort()

IO.puts("Reproducibility test:")
IO.puts("  Sample 1 (seed=12345) == Sample 2 (seed=12345): #{sample1_ids == sample2_ids}")
IO.puts("  Sample 1 (seed=12345) == Sample 3 (seed=67890): #{sample1_ids == sample3_ids}")
IO.puts("")

# Strategy 5: Comparison of Sampling Methods
Logger.info("Strategy 5: Comparing Sampling Methods")
IO.puts("Evaluating representation quality across different sampling methods\n")

defmodule SamplingAnalysis do
  def analyze_representation(sample, original) do
    sample_subjects = MapSet.new(sample.items, & &1.metadata.subject)
    original_subjects = MapSet.new(original.items, & &1.metadata.subject)

    coverage = MapSet.size(sample_subjects) / MapSet.size(original_subjects)

    # Calculate distribution similarity (using simple difference)
    sample_dist = Enum.frequencies_by(sample.items, & &1.metadata.subject)
    original_dist = Enum.frequencies_by(original.items, & &1.metadata.subject)

    sample_size = length(sample.items)
    original_size = length(original.items)

    distribution_difference =
      original_subjects
      |> MapSet.to_list()
      |> Enum.map(fn subject ->
        sample_pct = Map.get(sample_dist, subject, 0) / sample_size
        original_pct = Map.get(original_dist, subject) / original_size
        abs(sample_pct - original_pct)
      end)
      |> Enum.sum()
      |> Kernel./(MapSet.size(original_subjects))

    %{
      subject_coverage: coverage,
      distribution_difference: distribution_difference
    }
  end
end

random_analysis = SamplingAnalysis.analyze_representation(random_sample, full_dataset)
stratified_analysis = SamplingAnalysis.analyze_representation(stratified_sample, full_dataset)

IO.puts("Representation Quality Metrics:")
IO.puts("\nRandom Sampling:")
IO.puts("  Subject Coverage: #{Float.round(random_analysis.subject_coverage * 100, 1)}%")

IO.puts(
  "  Avg Distribution Difference: #{Float.round(random_analysis.distribution_difference * 100, 2)}%"
)

IO.puts("\nStratified Sampling:")
IO.puts("  Subject Coverage: #{Float.round(stratified_analysis.subject_coverage * 100, 1)}%")

IO.puts(
  "  Avg Distribution Difference: #{Float.round(stratified_analysis.distribution_difference * 100, 2)}%"
)

IO.puts("\nRecommendation:")

if stratified_analysis.distribution_difference < random_analysis.distribution_difference do
  IO.puts("  ✓ Stratified sampling maintains better class balance")
else
  IO.puts("  Random sampling was sufficient for this dataset")
end

Logger.info("\n=== Sampling Strategies Example Completed ===")
