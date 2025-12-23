defmodule HfDatasetsEx.DatasetOpsTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.{Dataset, Features}

  @sample_items [
    %{id: "1", input: "What is 2+2?", expected: "4", metadata: %{difficulty: "easy"}},
    %{id: "2", input: "What is 3+3?", expected: "6", metadata: %{difficulty: "easy"}},
    %{id: "3", input: "What is 10*10?", expected: "100", metadata: %{difficulty: "medium"}},
    %{id: "4", input: "What is 15/3?", expected: "5", metadata: %{difficulty: "medium"}},
    %{id: "5", input: "What is sqrt(144)?", expected: "12", metadata: %{difficulty: "hard"}}
  ]

  setup do
    dataset = Dataset.new("test_math", "1.0", @sample_items, %{source: "test"})
    {:ok, dataset: dataset}
  end

  describe "map/2" do
    test "transforms each item", %{dataset: dataset} do
      result =
        Dataset.map(dataset, fn item ->
          Map.put(item, :transformed, true)
        end)

      assert %Dataset{} = result
      assert Enum.all?(result.items, fn item -> item[:transformed] == true end)
      assert length(result.items) == 5
    end

    test "preserves dataset metadata", %{dataset: dataset} do
      result = Dataset.map(dataset, & &1)
      assert result.name == dataset.name
      assert result.version == dataset.version
      assert result.metadata.source == "test"
    end
  end

  describe "filter/2" do
    test "filters items by predicate", %{dataset: dataset} do
      result =
        Dataset.filter(dataset, fn item ->
          item.metadata.difficulty == "easy"
        end)

      assert %Dataset{} = result
      assert length(result.items) == 2
      assert Enum.all?(result.items, fn item -> item.metadata.difficulty == "easy" end)
    end

    test "returns empty dataset when no matches", %{dataset: dataset} do
      result = Dataset.filter(dataset, fn _ -> false end)
      assert result.items == []
    end

    test "updates total_items in metadata", %{dataset: dataset} do
      result = Dataset.filter(dataset, fn item -> item.metadata.difficulty == "hard" end)
      assert result.metadata.total_items == 1
    end
  end

  describe "shuffle/1" do
    test "randomizes item order", %{dataset: dataset} do
      # Run multiple times to ensure it's actually shuffling
      results = for _ <- 1..10, do: Dataset.shuffle(dataset).items

      # At least one should be different from original order
      original_ids = Enum.map(dataset.items, & &1.id)
      shuffled_ids = Enum.map(results, fn items -> Enum.map(items, & &1.id) end)

      # Not all should match the original (extremely unlikely with random shuffle)
      assert Enum.any?(shuffled_ids, fn ids -> ids != original_ids end)
    end

    test "preserves all items", %{dataset: dataset} do
      result = Dataset.shuffle(dataset)
      assert length(result.items) == length(dataset.items)

      original_ids = Enum.map(dataset.items, & &1.id) |> Enum.sort()
      result_ids = Enum.map(result.items, & &1.id) |> Enum.sort()
      assert result_ids == original_ids
    end

    test "shuffle with seed produces deterministic results", %{dataset: dataset} do
      result1 = Dataset.shuffle(dataset, seed: 42)
      result2 = Dataset.shuffle(dataset, seed: 42)

      assert Enum.map(result1.items, & &1.id) == Enum.map(result2.items, & &1.id)
    end
  end

  describe "select/2" do
    test "selects specific columns", %{dataset: dataset} do
      result = Dataset.select(dataset, [:id, :input])

      assert %Dataset{} = result
      first_item = hd(result.items)
      assert Map.has_key?(first_item, :id)
      assert Map.has_key?(first_item, :input)
      refute Map.has_key?(first_item, :expected)
      refute Map.has_key?(first_item, :metadata)
    end

    test "handles string keys", %{dataset: _dataset} do
      # Create dataset with string keys
      string_items =
        Enum.map(@sample_items, fn item ->
          Map.new(item, fn {k, v} -> {to_string(k), v} end)
        end)

      string_dataset = Dataset.new("test", "1.0", string_items)

      result = Dataset.select(string_dataset, ["id", "input"])
      first_item = hd(result.items)
      assert Map.has_key?(first_item, "id")
      assert Map.has_key?(first_item, "input")
    end
  end

  describe "select/2 with indices" do
    test "selects by index list", %{dataset: dataset} do
      result = Dataset.select(dataset, [0, 2, 4])

      assert Enum.map(result.items, & &1.id) == ["1", "3", "5"]
    end

    test "selects by range", %{dataset: dataset} do
      result = Dataset.select(dataset, 1..3)

      assert Enum.map(result.items, & &1.id) == ["2", "3", "4"]
    end
  end

  describe "take/2" do
    test "takes first N items", %{dataset: dataset} do
      result = Dataset.take(dataset, 3)

      assert length(result.items) == 3
      assert Enum.map(result.items, & &1.id) == ["1", "2", "3"]
    end

    test "takes all if N > length", %{dataset: dataset} do
      result = Dataset.take(dataset, 100)
      assert length(result.items) == 5
    end

    test "takes zero returns empty", %{dataset: dataset} do
      result = Dataset.take(dataset, 0)
      assert result.items == []
    end
  end

  describe "skip/2" do
    test "skips first N items", %{dataset: dataset} do
      result = Dataset.skip(dataset, 2)

      assert length(result.items) == 3
      assert Enum.map(result.items, & &1.id) == ["3", "4", "5"]
    end

    test "skip all returns empty", %{dataset: dataset} do
      result = Dataset.skip(dataset, 10)
      assert result.items == []
    end

    test "skip zero returns all", %{dataset: dataset} do
      result = Dataset.skip(dataset, 0)
      assert length(result.items) == 5
    end
  end

  describe "batch/2" do
    test "groups items into batches", %{dataset: dataset} do
      batches = Dataset.batch(dataset, 2)

      assert length(batches) == 3
      assert length(Enum.at(batches, 0).items) == 2
      assert length(Enum.at(batches, 1).items) == 2
      assert length(Enum.at(batches, 2).items) == 1
    end

    test "single batch when size >= items", %{dataset: dataset} do
      batches = Dataset.batch(dataset, 10)
      assert length(batches) == 1
      assert length(hd(batches).items) == 5
    end

    test "each batch is a Dataset", %{dataset: dataset} do
      batches = Dataset.batch(dataset, 2)
      assert Enum.all?(batches, fn b -> %Dataset{} = b end)
    end
  end

  describe "concat/2" do
    test "concatenates two datasets", %{dataset: dataset} do
      other_items = [
        %{id: "6", input: "What is 1+1?", expected: "2"}
      ]

      other = Dataset.new("other", "1.0", other_items)

      result = Dataset.concat(dataset, other)

      assert length(result.items) == 6
      assert List.last(result.items).id == "6"
    end

    test "preserves first dataset name", %{dataset: dataset} do
      other = Dataset.new("other", "1.0", [])
      result = Dataset.concat(dataset, other)
      assert result.name == dataset.name
    end
  end

  describe "concat/1 with list" do
    test "concatenates list of datasets", %{dataset: dataset} do
      d1 = Dataset.new("d1", "1.0", [%{id: "a", input: "x", expected: "y"}])
      d2 = Dataset.new("d2", "1.0", [%{id: "b", input: "x", expected: "y"}])

      result = Dataset.concat([dataset, d1, d2])

      assert length(result.items) == 7
    end

    test "returns first when single dataset", %{dataset: dataset} do
      result = Dataset.concat([dataset])
      assert result == dataset
    end
  end

  describe "slice/3" do
    test "slices from start to end", %{dataset: dataset} do
      result = Dataset.slice(dataset, 1, 3)

      assert length(result.items) == 3
      assert Enum.map(result.items, & &1.id) == ["2", "3", "4"]
    end

    test "slice with negative start counts from end", %{dataset: dataset} do
      result = Dataset.slice(dataset, -2, 2)
      assert Enum.map(result.items, & &1.id) == ["4", "5"]
    end
  end

  describe "split/2" do
    test "splits dataset by ratio", %{dataset: dataset} do
      {train, test} = Dataset.split(dataset, 0.8)

      assert length(train.items) == 4
      assert length(test.items) == 1
    end

    test "splits with specific sizes", %{dataset: dataset} do
      {train, test} = Dataset.split(dataset, train_size: 3, test_size: 2)

      assert length(train.items) == 3
      assert length(test.items) == 2
    end
  end

  describe "shard/2" do
    test "creates shards of dataset", %{dataset: dataset} do
      shards = Dataset.shard(dataset, num_shards: 3)

      assert length(shards) == 3
      total = Enum.sum(Enum.map(shards, fn s -> length(s.items) end))
      assert total == 5
    end

    test "returns single shard by index", %{dataset: dataset} do
      shard = Dataset.shard(dataset, num_shards: 3, index: 0)

      assert %Dataset{} = shard
      assert length(shard.items) > 0
    end
  end

  describe "rename_column/3" do
    test "renames a column", %{dataset: dataset} do
      result = Dataset.rename_column(dataset, :input, :prompt)

      first_item = hd(result.items)
      assert Map.has_key?(first_item, :prompt)
      refute Map.has_key?(first_item, :input)
    end
  end

  describe "add_column/3" do
    test "adds a column with function", %{dataset: dataset} do
      result = Dataset.add_column(dataset, :index, fn _item, idx -> idx end)

      assert hd(result.items).index == 0
      assert Enum.at(result.items, 4).index == 4
    end
  end

  describe "remove_columns/2" do
    test "removes specified columns", %{dataset: dataset} do
      result = Dataset.remove_columns(dataset, [:metadata])

      first_item = hd(result.items)
      refute Map.has_key?(first_item, :metadata)
      assert Map.has_key?(first_item, :id)
      assert Map.has_key?(first_item, :input)
    end
  end

  describe "unique/2" do
    test "removes duplicates by column" do
      items = [
        %{id: "1", category: "a", value: 1},
        %{id: "2", category: "a", value: 2},
        %{id: "3", category: "b", value: 3}
      ]

      dataset = Dataset.new("test", "1.0", items)

      result = Dataset.unique(dataset, :category)

      assert length(result.items) == 2
    end
  end

  describe "sort/2" do
    test "sorts by column ascending", %{dataset: dataset} do
      result = Dataset.sort(dataset, :id, :desc)

      assert Enum.map(result.items, & &1.id) == ["5", "4", "3", "2", "1"]
    end

    test "sorts by column descending", %{dataset: dataset} do
      result = Dataset.sort(dataset, :id, :asc)

      assert Enum.map(result.items, & &1.id) == ["1", "2", "3", "4", "5"]
    end
  end

  describe "flatten/2" do
    test "flattens nested column" do
      items = [
        %{id: "1", nested: %{a: 1, b: 2}},
        %{id: "2", nested: %{a: 3, b: 4}}
      ]

      dataset = Dataset.new("test", "1.0", items)

      result = Dataset.flatten(dataset, :nested)

      first_item = hd(result.items)
      assert first_item[:nested_a] == 1
      assert first_item[:nested_b] == 2
    end
  end

  describe "to_list/1" do
    test "returns items as list", %{dataset: dataset} do
      items = Dataset.to_list(dataset)
      assert is_list(items)
      assert length(items) == 5
    end
  end

  describe "num_items/1" do
    test "returns item count", %{dataset: dataset} do
      assert Dataset.num_items(dataset) == 5
    end
  end

  describe "column_names/1" do
    test "returns column names", %{dataset: dataset} do
      names = Dataset.column_names(dataset)
      assert :id in names
      assert :input in names
      assert :expected in names
    end
  end

  describe "from_list/1" do
    test "builds dataset with defaults" do
      items = [%{id: "a", input: "x", expected: "y"}]
      dataset = Dataset.from_list(items)

      assert dataset.name == "dataset"
      assert dataset.version == "1.0"
      assert dataset.items == items
    end
  end

  describe "from_dataframe/1" do
    test "builds dataset from Explorer dataframe" do
      df = Explorer.DataFrame.new(%{"id" => [1, 2], "text" => ["alpha", "beta"]})
      dataset = Dataset.from_dataframe(df, name: "df_test")

      assert dataset.name == "df_test"
      assert length(dataset.items) == 2
      assert Map.has_key?(hd(dataset.items), "id")
    end
  end

  describe "features integration" do
    test "infers features when not provided" do
      items = [%{id: "1", input: "x", expected: "y"}]
      dataset = Dataset.new("test", "1.0", items)

      assert %Features{} = dataset.features
      assert Map.has_key?(dataset.features.schema, "id")
    end

    test "uses provided features" do
      items = [%{id: "1", input: "x", expected: "y"}]
      features = Features.new(%{"id" => HfDatasetsEx.Features.Value.string()})
      dataset = Dataset.new("test", "1.0", items, %{}, features)

      assert dataset.features == features
    end
  end

  describe "Enumerable protocol" do
    test "supports Enum.count", %{dataset: dataset} do
      assert Enum.count(dataset) == 5
    end

    test "supports Enum.map", %{dataset: dataset} do
      ids = Enum.map(dataset, & &1.id)
      assert ids == ["1", "2", "3", "4", "5"]
    end

    test "supports Enum.filter", %{dataset: dataset} do
      easy = Enum.filter(dataset, fn item -> item.metadata.difficulty == "easy" end)
      assert length(easy) == 2
    end

    test "supports for comprehension", %{dataset: dataset} do
      ids = for item <- dataset, do: item.id
      assert ids == ["1", "2", "3", "4", "5"]
    end
  end

  describe "Access behaviour" do
    test "supports bracket access by index", %{dataset: dataset} do
      assert dataset[0].id == "1"
      assert dataset[4].id == "5"
    end

    test "supports negative index", %{dataset: dataset} do
      assert dataset[-1].id == "5"
    end

    test "supports get_and_update", %{dataset: dataset} do
      {old, new} =
        Access.get_and_update(dataset, 0, fn item ->
          {item, Map.put(item, :updated, true)}
        end)

      assert old.id == "1"
      assert new[0].updated == true
    end
  end
end
