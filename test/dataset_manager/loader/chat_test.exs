defmodule HfDatasetsEx.Loader.ChatTest do
  use TestSupport.HfCase

  alias HfDatasetsEx.Loader.Chat
  alias HfDatasetsEx.Types.Conversation

  describe "available_datasets/0" do
    test "returns list of available datasets" do
      datasets = Chat.available_datasets()

      assert :tulu3_sft in datasets
      assert :no_robots in datasets
    end
  end

  describe "load/2" do
    # Use no_robots for tests - it's a smaller dataset (1 file vs 6 for tulu3_sft)
    test "loads chat data" do
      {:ok, dataset} = Chat.load(:no_robots, TestHelper.data_opts())

      assert dataset.name == "no_robots"
      assert dataset.items != []
    end

    test "respects sample_size option" do
      {:ok, dataset} = Chat.load(:no_robots, TestHelper.data_opts(sample_size: 1))

      assert length(dataset.items) == 1
    end

    test "items have correct structure" do
      {:ok, dataset} = Chat.load(:no_robots, TestHelper.data_opts(sample_size: 1))

      first = hd(dataset.items)
      assert is_binary(first.id)
      assert is_map(first.input)
      assert Map.has_key?(first.input, :conversation)
      assert is_struct(first.input.conversation, Conversation)
    end
  end

  describe "load/2 with unknown dataset" do
    test "returns error for unknown dataset" do
      {:error, {:unknown_dataset, :unknown, available}} = Chat.load(:unknown)

      assert is_list(available)
    end
  end

  describe "load/2 with real data" do
    @describetag :live
    @tag timeout: 120_000

    test "loads real No Robots data from HuggingFace" do
      {:ok, dataset} = Chat.load(:no_robots, sample_size: 10)

      assert dataset.name == "no_robots"
      assert length(dataset.items) <= 10
      assert dataset.metadata.source =~ "huggingface"
    end
  end
end
