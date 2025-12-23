defmodule HfDatasetsEx.Loader.PreferenceTest do
  use TestSupport.HfCase

  alias HfDatasetsEx.Loader.Preference
  alias HfDatasetsEx.Types.{Comparison, LabeledComparison}

  describe "available_datasets/0" do
    test "returns list of available datasets" do
      datasets = Preference.available_datasets()

      assert :hh_rlhf in datasets
      assert :helpsteer3 in datasets
      assert :ultrafeedback in datasets
    end
  end

  describe "load/2" do
    test "loads preference data" do
      {:ok, dataset} = Preference.load(:hh_rlhf, TestHelper.data_opts())

      assert dataset.name == "hh_rlhf"
      assert length(dataset.items) > 0
    end

    test "respects sample_size option" do
      {:ok, dataset} = Preference.load(:helpsteer3, TestHelper.data_opts(sample_size: 1))

      assert length(dataset.items) == 1
    end

    test "items have correct structure" do
      {:ok, dataset} = Preference.load(:ultrafeedback, TestHelper.data_opts(sample_size: 1))

      first = hd(dataset.items)
      assert is_binary(first.id)
      assert is_map(first.input)
      assert Map.has_key?(first.input, :comparison)
      assert is_struct(first.input.comparison, Comparison)
      assert is_struct(first.expected, LabeledComparison)
    end
  end

  describe "load/2 with unknown dataset" do
    test "returns error for unknown dataset" do
      {:error, {:unknown_dataset, :unknown, available}} = Preference.load(:unknown)

      assert is_list(available)
    end
  end
end
