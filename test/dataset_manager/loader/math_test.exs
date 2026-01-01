defmodule HfDatasetsEx.Loader.MathTest do
  use TestSupport.HfCase

  alias HfDatasetsEx.Loader.Math

  describe "available_datasets/0" do
    test "returns list of available datasets" do
      datasets = Math.available_datasets()

      assert :math_500 in datasets
      assert :hendrycks_math in datasets
      assert :deepmath in datasets
      assert :polaris in datasets
    end
  end

  describe "extract_boxed_answer/1" do
    test "extracts simple boxed answer" do
      assert Math.extract_boxed_answer("The answer is \\boxed{42}") == "42"
    end

    test "extracts expression from boxed" do
      assert Math.extract_boxed_answer("\\boxed{x^2 + 1}") == "x^2 + 1"
    end

    test "extracts nested braces" do
      assert Math.extract_boxed_answer("\\boxed{\\frac{1}{2}}") == "\\frac{1}{2}"
    end

    test "returns nil for no boxed answer" do
      assert Math.extract_boxed_answer("No boxed answer here") == nil
    end

    test "returns nil for nil input" do
      assert Math.extract_boxed_answer(nil) == nil
    end
  end

  describe "load/2" do
    test "loads math data" do
      {:ok, dataset} = Math.load(:math_500, TestHelper.data_opts())

      assert dataset.name == "math_500"
      assert dataset.items != []
    end

    test "respects sample_size option" do
      {:ok, dataset} = Math.load(:hendrycks_math, TestHelper.data_opts(sample_size: 1))

      assert length(dataset.items) == 1
    end

    test "items have correct structure" do
      {:ok, dataset} = Math.load(:math_500, TestHelper.data_opts(sample_size: 1))

      first = hd(dataset.items)
      assert is_binary(first.id)
      assert is_map(first.input)
      assert Map.has_key?(first.input, :problem)
      assert is_binary(first.expected) or is_nil(first.expected)
      assert is_map(first.metadata)
    end
  end

  describe "load/2 with unknown dataset" do
    test "returns error for unknown dataset" do
      {:error, {:unknown_dataset, :unknown, available}} = Math.load(:unknown)

      assert is_list(available)
    end
  end
end
