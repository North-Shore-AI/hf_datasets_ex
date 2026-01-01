defmodule HfDatasetsEx.DatasetSearchTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Dataset

  describe "add_index/3" do
    test "creates index from column" do
      dataset =
        Dataset.from_list([
          %{"id" => 1, "embedding" => [1.0, 0.0]},
          %{"id" => 2, "embedding" => [0.0, 1.0]},
          %{"id" => 3, "embedding" => [0.707, 0.707]}
        ])

      indexed = Dataset.add_index(dataset, "embedding")

      assert get_in(indexed.metadata, [:indices, "embedding"]) != nil
    end
  end

  describe "get_nearest_examples/4" do
    test "returns nearest examples" do
      dataset =
        Dataset.from_list([
          %{"id" => 1, "embedding" => [1.0, 0.0, 0.0]},
          %{"id" => 2, "embedding" => [0.0, 1.0, 0.0]},
          %{"id" => 3, "embedding" => [0.0, 0.0, 1.0]}
        ])

      indexed = Dataset.add_index(dataset, "embedding")

      query = Nx.tensor([1.0, 0.0, 0.0])
      {scores, examples} = Dataset.get_nearest_examples(indexed, "embedding", query, k: 2)

      assert length(scores) == 2
      assert length(examples) == 2

      assert hd(examples)["id"] == 1
    end

    test "raises if no index" do
      dataset = Dataset.from_list([%{"id" => 1}])

      assert_raise ArgumentError, ~r/No index found/, fn ->
        Dataset.get_nearest_examples(dataset, "embedding", Nx.tensor([1.0]))
      end
    end
  end

  describe "drop_index/2" do
    test "removes index" do
      dataset =
        Dataset.from_list([
          %{"embedding" => [1.0, 0.0]}
        ])

      indexed = Dataset.add_index(dataset, "embedding")
      dropped = Dataset.drop_index(indexed, "embedding")

      assert get_in(dropped.metadata, [:indices, "embedding"]) == nil
    end
  end
end
