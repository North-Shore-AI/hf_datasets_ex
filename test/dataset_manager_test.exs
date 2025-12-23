defmodule DatasetManagerTest do
  use TestSupport.HfCase
  doctest HfDatasetsEx

  alias HfDatasetsEx.{Dataset, Cache}

  setup do
    Cache.clear_all()
    :ok
  end

  describe "load/2" do
    test "loads MMLU STEM dataset" do
      {:ok, dataset} = HfDatasetsEx.load(:mmlu_stem, TestHelper.data_opts(sample_size: 50))

      assert dataset.name == "mmlu_stem"
      assert dataset.version == "1.0"
      assert length(dataset.items) <= 50
      assert dataset.metadata.domain == "STEM"
    end

    test "loads HumanEval dataset" do
      {:ok, dataset} = HfDatasetsEx.load(:humaneval, TestHelper.data_opts(sample_size: 10))

      assert dataset.name == "humaneval"
      assert dataset.version == "1.0"
      assert length(dataset.items) <= 10
      assert dataset.metadata.domain == "code_generation"
    end

    test "loads GSM8K dataset" do
      {:ok, dataset} = HfDatasetsEx.load(:gsm8k, TestHelper.data_opts(sample_size: 20))

      assert dataset.name == "gsm8k"
      assert dataset.version == "1.0"
      assert length(dataset.items) <= 20
      assert dataset.metadata.domain == "math_word_problems"
    end

    test "returns error for unknown dataset" do
      assert {:error, {:unknown_dataset, :unknown}} = HfDatasetsEx.load(:unknown)
    end

    test "caches loaded datasets" do
      {:ok, dataset1} = HfDatasetsEx.load(:mmlu_stem, TestHelper.data_opts(sample_size: 10))
      {:ok, dataset2} = HfDatasetsEx.load(:mmlu_stem, TestHelper.data_opts(sample_size: 10))

      assert dataset1.name == dataset2.name
      assert dataset1.metadata.checksum == dataset2.metadata.checksum
    end

    test "respects cache: false option" do
      {:ok, dataset} =
        HfDatasetsEx.load(:mmlu_stem, TestHelper.data_opts(sample_size: 10, cache: false))

      assert dataset.name == "mmlu_stem"
      assert {:error, :not_cached} = Cache.get(:mmlu_stem)
    end
  end

  describe "random_sample/2" do
    test "creates random sample of specified size" do
      {:ok, dataset} = HfDatasetsEx.load(:mmlu_stem, TestHelper.data_opts(sample_size: 2))
      {:ok, sample} = HfDatasetsEx.random_sample(dataset, size: 1)

      assert length(sample.items) == 1
      assert sample.metadata.sample_method == :random
      assert sample.metadata.sample_size == 1
      assert sample.metadata.original_size == length(dataset.items)
    end

    test "uses seed for reproducible sampling" do
      {:ok, dataset} = HfDatasetsEx.load(:mmlu_stem, TestHelper.data_opts(sample_size: 2))

      {:ok, sample1} = HfDatasetsEx.random_sample(dataset, size: 1, seed: 42)
      {:ok, sample2} = HfDatasetsEx.random_sample(dataset, size: 1, seed: 42)

      # Same seed should produce same sample
      assert Enum.map(sample1.items, & &1.id) == Enum.map(sample2.items, & &1.id)
    end
  end

  describe "stratified_sample/2" do
    test "maintains distribution of stratification field" do
      {:ok, dataset} = HfDatasetsEx.load(:mmlu_stem, TestHelper.data_opts(sample_size: 100))

      {:ok, sample} =
        HfDatasetsEx.stratified_sample(dataset,
          size: 30,
          strata_field: [:metadata, :subject]
        )

      assert length(sample.items) <= 30
      assert sample.metadata.sample_method == :stratified
    end

    test "returns error when missing required options" do
      {:ok, dataset} = HfDatasetsEx.load(:mmlu_stem, TestHelper.data_opts(sample_size: 100))

      assert {:error, :missing_required_option} = HfDatasetsEx.stratified_sample(dataset)
    end
  end

  describe "k_fold/2" do
    test "creates k-fold splits" do
      {:ok, dataset} = HfDatasetsEx.load(:mmlu_stem, TestHelper.data_opts(sample_size: 50))
      {:ok, folds} = HfDatasetsEx.k_fold(dataset, k: 5)

      assert length(folds) == 5

      Enum.each(folds, fn {train, test} ->
        assert is_struct(train, Dataset)
        assert is_struct(test, Dataset)
        assert length(train.items) + length(test.items) == length(dataset.items)
      end)
    end

    test "creates folds without shuffle" do
      {:ok, dataset} = HfDatasetsEx.load(:mmlu_stem, TestHelper.data_opts(sample_size: 50))
      {:ok, folds} = HfDatasetsEx.k_fold(dataset, k: 5, shuffle: false)

      assert length(folds) == 5
    end
  end

  describe "train_test_split/2" do
    test "splits dataset into train and test sets" do
      {:ok, dataset} = HfDatasetsEx.load(:mmlu_stem, TestHelper.data_opts(sample_size: 100))
      {:ok, {train, test}} = HfDatasetsEx.train_test_split(dataset, test_size: 0.2)

      total = length(dataset.items)
      assert length(train.items) + length(test.items) == total
      assert length(test.items) == round(total * 0.2)
    end
  end

  describe "cache management" do
    test "lists cached datasets" do
      {:ok, _dataset} = HfDatasetsEx.load(:mmlu_stem, TestHelper.data_opts(sample_size: 10))

      cached = HfDatasetsEx.list_cached()
      assert is_list(cached)
    end

    test "invalidates specific dataset cache" do
      {:ok, _dataset} = HfDatasetsEx.load(:mmlu_stem, TestHelper.data_opts(sample_size: 10))

      assert :ok = HfDatasetsEx.invalidate_cache(:mmlu_stem)
      assert {:error, :not_cached} = Cache.get(:mmlu_stem)
    end

    test "clears all cache" do
      {:ok, _dataset1} = HfDatasetsEx.load(:mmlu_stem, TestHelper.data_opts(sample_size: 10))
      {:ok, _dataset2} = HfDatasetsEx.load(:gsm8k, TestHelper.data_opts(sample_size: 10))

      assert :ok = HfDatasetsEx.clear_cache()

      assert {:error, :not_cached} = Cache.get(:mmlu_stem)
      assert {:error, :not_cached} = Cache.get(:gsm8k)
    end
  end
end
