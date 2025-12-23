defmodule HfDatasetsEx.IterableDatasetTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.{Dataset, IterableDataset}

  @sample_items [
    %{id: "1", input: "What is 2+2?", expected: "4"},
    %{id: "2", input: "What is 3+3?", expected: "6"},
    %{id: "3", input: "What is 4+4?", expected: "8"},
    %{id: "4", input: "What is 5+5?", expected: "10"},
    %{id: "5", input: "What is 6+6?", expected: "12"}
  ]

  describe "from_stream/2" do
    test "creates from enumerable" do
      stream = Stream.map(@sample_items, & &1)
      iterable = IterableDataset.from_stream(stream, name: "test")

      assert %IterableDataset{} = iterable
      assert iterable.name == "test"
    end

    test "creates from list" do
      iterable = IterableDataset.from_stream(@sample_items, name: "test")
      assert %IterableDataset{} = iterable
    end
  end

  describe "from_dataset/1" do
    test "converts Dataset to IterableDataset" do
      dataset = Dataset.new("test", "1.0", @sample_items)
      iterable = IterableDataset.from_dataset(dataset)

      assert %IterableDataset{} = iterable
      assert iterable.name == "test"
    end
  end

  describe "take/2" do
    test "takes first N items" do
      iterable = IterableDataset.from_stream(@sample_items, name: "test")
      items = IterableDataset.take(iterable, 3)

      assert length(items) == 3
      assert Enum.map(items, & &1.id) == ["1", "2", "3"]
    end

    test "returns all if N > stream length" do
      iterable = IterableDataset.from_stream(@sample_items, name: "test")
      items = IterableDataset.take(iterable, 100)

      assert length(items) == 5
    end
  end

  describe "skip/2" do
    test "skips first N items and returns rest" do
      iterable = IterableDataset.from_stream(@sample_items, name: "test")
      result = IterableDataset.skip(iterable, 2)

      items = IterableDataset.to_list(result)
      assert length(items) == 3
      assert Enum.map(items, & &1.id) == ["3", "4", "5"]
    end
  end

  describe "map/2" do
    test "transforms stream lazily" do
      iterable =
        IterableDataset.from_stream(@sample_items, name: "test")
        |> IterableDataset.map(fn item -> Map.put(item, :processed, true) end)

      items = IterableDataset.take(iterable, 2)
      assert Enum.all?(items, & &1[:processed])
    end
  end

  describe "filter/2" do
    test "filters stream lazily" do
      iterable =
        IterableDataset.from_stream(@sample_items, name: "test")
        |> IterableDataset.filter(fn item -> item.id in ["1", "3", "5"] end)

      items = IterableDataset.to_list(iterable)
      assert length(items) == 3
    end
  end

  describe "batch/2" do
    test "groups items into batches" do
      iterable = IterableDataset.from_stream(@sample_items, name: "test")
      batched = IterableDataset.batch(iterable, 2)

      batches = IterableDataset.to_list(batched)
      assert length(batches) == 3
      assert length(hd(batches)) == 2
      assert length(List.last(batches)) == 1
    end
  end

  describe "shuffle/2" do
    test "shuffles with buffer" do
      # Large buffer to allow real shuffling
      iterable =
        IterableDataset.from_stream(@sample_items, name: "test")
        |> IterableDataset.shuffle(buffer_size: 5)

      items = IterableDataset.to_list(iterable)
      assert length(items) == 5
    end

    test "shuffles deterministically with seed" do
      stream1 =
        IterableDataset.from_stream(@sample_items, name: "test")
        |> IterableDataset.shuffle(buffer_size: 5, seed: 42)
        |> IterableDataset.to_list()

      stream2 =
        IterableDataset.from_stream(@sample_items, name: "test")
        |> IterableDataset.shuffle(buffer_size: 5, seed: 42)
        |> IterableDataset.to_list()

      assert Enum.map(stream1, & &1.id) == Enum.map(stream2, & &1.id)
    end
  end

  describe "to_list/1" do
    test "materializes stream to list" do
      iterable = IterableDataset.from_stream(@sample_items, name: "test")
      items = IterableDataset.to_list(iterable)

      assert is_list(items)
      assert length(items) == 5
    end
  end

  describe "to_dataset/1" do
    test "materializes to Dataset struct" do
      iterable = IterableDataset.from_stream(@sample_items, name: "test")
      dataset = IterableDataset.to_dataset(iterable)

      assert %Dataset{} = dataset
      assert dataset.name == "test"
      assert length(dataset.items) == 5
    end

    test "preserves transformations" do
      dataset =
        IterableDataset.from_stream(@sample_items, name: "test")
        |> IterableDataset.filter(fn item -> item.id in ["1", "2"] end)
        |> IterableDataset.map(fn item -> Map.put(item, :processed, true) end)
        |> IterableDataset.to_dataset()

      assert length(dataset.items) == 2
      assert Enum.all?(dataset.items, & &1[:processed])
    end
  end

  describe "Enumerable protocol" do
    test "supports Enum.take" do
      iterable = IterableDataset.from_stream(@sample_items, name: "test")
      items = Enum.take(iterable, 2)

      assert length(items) == 2
    end

    test "supports Enum.map" do
      iterable = IterableDataset.from_stream(@sample_items, name: "test")
      ids = Enum.map(iterable, & &1.id)

      assert ids == ["1", "2", "3", "4", "5"]
    end

    test "supports for comprehension" do
      iterable = IterableDataset.from_stream(@sample_items, name: "test")
      ids = for item <- iterable, do: item.id

      assert ids == ["1", "2", "3", "4", "5"]
    end
  end

  describe "chained operations" do
    test "lazily chains multiple operations" do
      # Counter to verify laziness
      counter = :counters.new(1, [:atomics])

      items =
        Stream.map(@sample_items, fn item ->
          :counters.add(counter, 1, 1)
          item
        end)

      result =
        IterableDataset.from_stream(items, name: "test")
        |> IterableDataset.filter(fn item -> item.id != "3" end)
        |> IterableDataset.map(fn item -> Map.put(item, :processed, true) end)
        |> IterableDataset.take(2)

      # Only 2 items should have been processed
      assert length(result) == 2
      assert :counters.get(counter, 1) == 2
    end
  end

  describe "with_info/2" do
    test "adds metadata to iterable" do
      iterable =
        IterableDataset.from_stream(@sample_items, name: "test")
        |> IterableDataset.with_info(%{source: "local", format: "jsonl"})

      assert iterable.info.source == "local"
      assert iterable.info.format == "jsonl"
    end
  end
end
