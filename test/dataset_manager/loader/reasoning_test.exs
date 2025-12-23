defmodule HfDatasetsEx.Loader.ReasoningTest do
  use TestSupport.HfCase

  alias HfDatasetsEx.Loader.Reasoning

  describe "load/2" do
    test "loads reasoning data" do
      {:ok, dataset} = Reasoning.load(:open_thoughts3, TestHelper.data_opts())

      assert dataset.name == "open_thoughts3"
      assert length(dataset.items) > 0
      assert dataset.metadata.domain == "reasoning"
    end

    test "respects sample_size option" do
      {:ok, dataset} = Reasoning.load(:open_thoughts3, TestHelper.data_opts(sample_size: 1))

      assert length(dataset.items) == 1
    end

    test "items have correct structure" do
      {:ok, dataset} = Reasoning.load(:open_thoughts3, TestHelper.data_opts(sample_size: 1))

      first = hd(dataset.items)
      assert is_binary(first.id)
      assert is_map(first.input)
      assert Map.has_key?(first.input, :prompt)
      assert is_map(first.expected)
      assert Map.has_key?(first.expected, :reasoning)
      assert is_map(first.metadata)
      assert Map.has_key?(first.metadata, :has_reasoning)
    end

    test "deepmath_reasoning works" do
      {:ok, dataset} = Reasoning.load(:deepmath_reasoning, TestHelper.data_opts(sample_size: 1))

      assert dataset.name == "deepmath_reasoning"
      assert length(dataset.items) == 1
    end
  end

  describe "available_datasets/0" do
    test "returns list of available datasets" do
      datasets = Reasoning.available_datasets()

      assert :open_thoughts3 in datasets
      assert :deepmath_reasoning in datasets
    end
  end

  describe "error handling" do
    test "returns error for unknown dataset" do
      assert {:error, {:unknown_dataset, :nonexistent, _}} =
               Reasoning.load(:nonexistent, TestHelper.data_opts())
    end
  end

  describe "load/2 with real data" do
    @describetag :live
    @tag timeout: 120_000

    test "loads real OpenThoughts3 data from HuggingFace" do
      {:ok, dataset} = Reasoning.load(:open_thoughts3, sample_size: 10)

      assert dataset.name == "open_thoughts3"
      assert length(dataset.items) == 10
      assert dataset.metadata.source =~ "huggingface"
    end

    @tag timeout: 120_000
    test "items have correct structure from HuggingFace" do
      {:ok, dataset} = Reasoning.load(:open_thoughts3, sample_size: 5)

      first = hd(dataset.items)
      assert is_binary(first.id)
      assert is_map(first.input)
      assert is_map(first.expected)
      assert is_map(first.metadata)
    end
  end
end
