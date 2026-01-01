defmodule HfDatasetsEx.DatasetCreationTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.{Dataset, IterableDataset}

  @fixtures_dir Path.join(__DIR__, "../fixtures")

  setup_all do
    File.mkdir_p!(@fixtures_dir)

    File.write!(Path.join(@fixtures_dir, "test.csv"), """
    name,age
    Alice,30
    Bob,25
    """)

    File.write!(Path.join(@fixtures_dir, "test.json"), """
    [{"name": "Alice", "age": 30}, {"name": "Bob", "age": 25}]
    """)

    File.write!(Path.join(@fixtures_dir, "test.jsonl"), """
    {"name": "Alice", "age": 30}
    {"name": "Bob", "age": 25}
    """)

    File.write!(Path.join(@fixtures_dir, "test.txt"), """
    Hello world
    How are you
    """)

    on_exit(fn -> File.rm_rf!(@fixtures_dir) end)

    :ok
  end

  describe "from_generator/2" do
    test "creates IterableDataset by default" do
      result =
        Dataset.from_generator(fn ->
          1..3 |> Stream.map(&%{"x" => &1})
        end)

      assert %IterableDataset{} = result
    end

    test "creates eager Dataset with :eager option" do
      result =
        Dataset.from_generator(
          fn -> 1..3 |> Stream.map(&%{"x" => &1}) end,
          eager: true
        )

      assert %Dataset{} = result
      assert Dataset.num_items(result) == 3
    end

    test "generator is evaluated lazily" do
      counter = :counters.new(1, [:atomics])

      result =
        Dataset.from_generator(fn ->
          Stream.map(1..10, fn x ->
            :counters.add(counter, 1, 1)
            %{"x" => x}
          end)
        end)

      assert :counters.get(counter, 1) == 0

      _ = result |> Enum.take(3)

      assert :counters.get(counter, 1) == 3
    end
  end

  describe "from_csv/2" do
    test "loads CSV file" do
      path = Path.join(@fixtures_dir, "test.csv")

      assert {:ok, dataset} = Dataset.from_csv(path)
      assert Dataset.num_items(dataset) == 2
      assert Dataset.column_names(dataset) == ["age", "name"]
    end

    test "handles missing file" do
      assert {:error, _} = Dataset.from_csv("/nonexistent.csv")
    end

    test "from_csv! raises on error" do
      assert_raise RuntimeError, fn ->
        Dataset.from_csv!("/nonexistent.csv")
      end
    end
  end

  describe "from_json/2" do
    test "loads JSON array file" do
      path = Path.join(@fixtures_dir, "test.json")

      assert {:ok, dataset} = Dataset.from_json(path)
      assert Dataset.num_items(dataset) == 2
    end

    test "loads JSONL file" do
      path = Path.join(@fixtures_dir, "test.jsonl")

      assert {:ok, dataset} = Dataset.from_json(path)
      assert Dataset.num_items(dataset) == 2
    end
  end

  describe "from_parquet/2" do
    setup do
      path = Path.join(@fixtures_dir, "test.parquet")

      df =
        Explorer.DataFrame.new(%{
          "name" => ["Alice", "Bob"],
          "age" => [30, 25]
        })

      Explorer.DataFrame.to_parquet(df, path)

      {:ok, path: path}
    end

    test "loads Parquet file", %{path: path} do
      assert {:ok, dataset} = Dataset.from_parquet(path)
      assert Dataset.num_items(dataset) == 2
    end

    test "selects specific columns", %{path: path} do
      assert {:ok, dataset} = Dataset.from_parquet(path, columns: ["name"])
      assert Dataset.column_names(dataset) == ["name"]
    end
  end

  describe "from_text/2" do
    test "loads text file" do
      path = Path.join(@fixtures_dir, "test.txt")

      assert {:ok, dataset} = Dataset.from_text(path)
      assert Dataset.num_items(dataset) == 2

      [first | _] = dataset.items
      assert Map.has_key?(first, "text")
    end

    test "uses custom column name" do
      path = Path.join(@fixtures_dir, "test.txt")

      assert {:ok, dataset} = Dataset.from_text(path, column: "content")

      [first | _] = dataset.items
      assert Map.has_key?(first, "content")
    end

    test "strips whitespace by default" do
      path = Path.join(@fixtures_dir, "test.txt")

      assert {:ok, dataset} = Dataset.from_text(path)

      [first | _] = dataset.items
      refute String.ends_with?(first["text"], "\n")
    end
  end
end
