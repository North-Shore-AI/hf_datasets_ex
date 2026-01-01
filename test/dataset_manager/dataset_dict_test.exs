defmodule HfDatasetsEx.DatasetDictTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.{Dataset, DatasetDict}

  @train_items [
    %{id: "1", input: "What is 2+2?", expected: "4"},
    %{id: "2", input: "What is 3+3?", expected: "6"},
    %{id: "3", input: "What is 4+4?", expected: "8"}
  ]

  @test_items [
    %{id: "t1", input: "What is 5+5?", expected: "10"},
    %{id: "t2", input: "What is 6+6?", expected: "12"}
  ]

  @validation_items [
    %{id: "v1", input: "What is 7+7?", expected: "14"}
  ]

  setup do
    train_ds = Dataset.new("math_train", "1.0", @train_items)
    test_ds = Dataset.new("math_test", "1.0", @test_items)
    validation_ds = Dataset.new("math_validation", "1.0", @validation_items)

    dataset_dict =
      DatasetDict.new(%{
        "train" => train_ds,
        "test" => test_ds,
        "validation" => validation_ds
      })

    {:ok,
     dataset_dict: dataset_dict,
     train_ds: train_ds,
     test_ds: test_ds,
     validation_ds: validation_ds}
  end

  describe "new/1" do
    test "creates a DatasetDict from map of datasets", %{dataset_dict: dataset_dict} do
      assert %DatasetDict{} = dataset_dict
      assert MapSet.size(dataset_dict.splits) == 3
    end

    test "accepts string or atom keys" do
      train = Dataset.new("train", "1.0", @train_items)

      dd1 = DatasetDict.new(%{"train" => train})
      dd2 = DatasetDict.new(%{train: train})

      assert DatasetDict.split_names(dd1) == ["train"]
      assert DatasetDict.split_names(dd2) == ["train"]
    end
  end

  describe "from_splits/1" do
    test "creates from keyword list" do
      train = Dataset.new("train", "1.0", @train_items)
      test = Dataset.new("test", "1.0", @test_items)

      dd = DatasetDict.from_splits(train: train, test: test)

      assert %DatasetDict{} = dd
      assert "train" in DatasetDict.split_names(dd)
      assert "test" in DatasetDict.split_names(dd)
    end
  end

  describe "get/2" do
    test "retrieves split by name", %{dataset_dict: dataset_dict, train_ds: train_ds} do
      result = DatasetDict.get(dataset_dict, "train")
      assert result.items == train_ds.items
    end

    test "retrieves by atom key", %{dataset_dict: dataset_dict} do
      result = DatasetDict.get(dataset_dict, :train)
      assert length(result.items) == 3
    end

    test "returns nil for missing split", %{dataset_dict: dataset_dict} do
      assert DatasetDict.get(dataset_dict, "nonexistent") == nil
    end
  end

  describe "Access behaviour" do
    test "supports bracket access", %{dataset_dict: dataset_dict} do
      assert dataset_dict["train"].items |> length() == 3
      assert dataset_dict["test"].items |> length() == 2
    end

    test "supports atom keys", %{dataset_dict: dataset_dict} do
      assert dataset_dict[:train].items |> length() == 3
    end
  end

  describe "split_names/1" do
    test "returns list of split names", %{dataset_dict: dataset_dict} do
      names = DatasetDict.split_names(dataset_dict)

      assert "train" in names
      assert "test" in names
      assert "validation" in names
      assert length(names) == 3
    end
  end

  describe "num_splits/1" do
    test "returns number of splits", %{dataset_dict: dataset_dict} do
      assert DatasetDict.num_splits(dataset_dict) == 3
    end
  end

  describe "put/3" do
    test "adds a new split", %{dataset_dict: dataset_dict} do
      new_split = Dataset.new("new", "1.0", [%{id: "x", input: "y", expected: "z"}])
      updated = DatasetDict.put(dataset_dict, "extra", new_split)

      assert DatasetDict.num_splits(updated) == 4
      assert "extra" in DatasetDict.split_names(updated)
    end

    test "replaces existing split", %{dataset_dict: dataset_dict} do
      new_train = Dataset.new("train_v2", "2.0", [%{id: "new1", input: "a", expected: "b"}])
      updated = DatasetDict.put(dataset_dict, "train", new_train)

      assert length(updated["train"].items) == 1
    end
  end

  describe "delete/2" do
    test "removes a split", %{dataset_dict: dataset_dict} do
      updated = DatasetDict.delete(dataset_dict, "validation")

      assert DatasetDict.num_splits(updated) == 2
      refute "validation" in DatasetDict.split_names(updated)
    end
  end

  describe "map/2" do
    test "applies function to all splits", %{dataset_dict: dataset_dict} do
      result =
        DatasetDict.map(dataset_dict, fn dataset ->
          Dataset.map(dataset, fn item -> Map.put(item, :processed, true) end)
        end)

      assert Enum.all?(result["train"].items, & &1[:processed])
      assert Enum.all?(result["test"].items, & &1[:processed])
    end
  end

  describe "filter/2" do
    test "filters each split", %{dataset_dict: dataset_dict} do
      # Only keep items with id starting with number
      result =
        DatasetDict.filter(dataset_dict, fn item ->
          String.match?(item.id, ~r/^\d/)
        end)

      assert length(result["train"].items) == 3
      assert result["test"].items == []
      assert result["validation"].items == []
    end
  end

  describe "select/2" do
    test "selects columns from all splits", %{dataset_dict: dataset_dict} do
      result = DatasetDict.select(dataset_dict, [:id, :input])

      first = hd(result["train"].items)
      assert Map.has_key?(first, :id)
      assert Map.has_key?(first, :input)
      refute Map.has_key?(first, :expected)
    end
  end

  describe "shuffle/1" do
    test "shuffles all splits", %{dataset_dict: dataset_dict} do
      # With seed for determinism
      result = DatasetDict.shuffle(dataset_dict, seed: 42)

      assert %DatasetDict{} = result
      assert length(result["train"].items) == 3
    end
  end

  describe "flatten/1" do
    test "combines all splits into single dataset", %{dataset_dict: dataset_dict} do
      combined = DatasetDict.flatten(dataset_dict)

      assert %Dataset{} = combined
      assert length(combined.items) == 6
    end
  end

  describe "to_map/1" do
    test "converts to plain map", %{dataset_dict: dataset_dict, train_ds: train_ds} do
      map = DatasetDict.to_map(dataset_dict)

      assert is_map(map)
      assert map["train"].items == train_ds.items
    end
  end

  describe "num_rows/1" do
    test "returns row counts per split", %{dataset_dict: dataset_dict} do
      counts = DatasetDict.num_rows(dataset_dict)

      assert counts["train"] == 3
      assert counts["test"] == 2
      assert counts["validation"] == 1
    end
  end

  describe "column_names/1" do
    test "returns column names per split", %{dataset_dict: dataset_dict} do
      names = DatasetDict.column_names(dataset_dict)

      assert Enum.sort(names["train"]) == [:expected, :id, :input]
      assert Enum.sort(names["test"]) == [:expected, :id, :input]
    end
  end

  describe "info/1" do
    test "returns summary info", %{dataset_dict: dataset_dict} do
      info = DatasetDict.info(dataset_dict)

      assert info.num_splits == 3
      assert info.total_items == 6
      assert info.splits["train"] == 3
      assert info.splits["test"] == 2
      assert info.splits["validation"] == 1
    end
  end

  describe "rename_split/3" do
    test "renames a split", %{dataset_dict: dataset_dict} do
      result = DatasetDict.rename_split(dataset_dict, "train", "training")

      assert "training" in DatasetDict.split_names(result)
      refute "train" in DatasetDict.split_names(result)
      assert length(result["training"].items) == 3
    end
  end

  describe "Enumerable protocol" do
    test "supports Enum.count", %{dataset_dict: dataset_dict} do
      assert Enum.count(dataset_dict) == 3
    end

    test "supports Enum.map", %{dataset_dict: dataset_dict} do
      names = Enum.map(dataset_dict, fn {name, _dataset} -> name end)
      assert "train" in names
      assert "test" in names
    end

    test "supports for comprehension", %{dataset_dict: dataset_dict} do
      counts = for {name, dataset} <- dataset_dict, do: {name, length(dataset.items)}
      assert {"train", 3} in counts
      assert {"test", 2} in counts
    end
  end
end
