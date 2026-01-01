defmodule HfDatasetsEx.ExportTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.{Dataset, Export}

  @temp_dir System.tmp_dir!()

  setup do
    dataset =
      Dataset.from_list([
        %{"name" => "Alice", "age" => 30, "city" => "NYC"},
        %{"name" => "Bob", "age" => 25, "city" => "LA"}
      ])

    {:ok, dataset: dataset}
  end

  describe "to_csv/3" do
    test "exports basic dataset to CSV", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_#{:rand.uniform(100_000)}.csv")

      assert :ok = Export.to_csv(dataset, path)
      assert File.exists?(path)

      content = File.read!(path)
      lines = String.split(content, "\n", trim: true)

      assert length(lines) == 3
      assert hd(lines) =~ "name"
      assert hd(lines) =~ "age"
    end

    test "handles values with commas", %{dataset: _dataset} do
      ds = Dataset.from_list([%{"text" => "hello, world"}])
      path = Path.join(@temp_dir, "test_comma_#{:rand.uniform(100_000)}.csv")

      assert :ok = Export.to_csv(ds, path)

      content = File.read!(path)
      assert content =~ "\"hello, world\""
    end

    test "handles values with quotes", %{dataset: _dataset} do
      ds = Dataset.from_list([%{"text" => "say \"hello\""}])
      path = Path.join(@temp_dir, "test_quote_#{:rand.uniform(100_000)}.csv")

      assert :ok = Export.to_csv(ds, path)

      content = File.read!(path)
      assert content =~ "\"say \"\"hello\"\"\""
    end

    test "respects :headers option", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_noheader_#{:rand.uniform(100_000)}.csv")

      assert :ok = Export.to_csv(dataset, path, headers: false)

      content = File.read!(path)
      lines = String.split(content, "\n", trim: true)

      assert length(lines) == 2
    end

    test "respects :columns option", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_cols_#{:rand.uniform(100_000)}.csv")

      assert :ok = Export.to_csv(dataset, path, columns: ["name", "age"])

      content = File.read!(path)
      refute content =~ "city"
    end
  end

  describe "to_json/3" do
    test "exports to JSON records format", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_#{:rand.uniform(100_000)}.json")

      assert :ok = Export.to_json(dataset, path)
      assert File.exists?(path)

      {:ok, data} = Jason.decode(File.read!(path))
      assert is_list(data)
      assert length(data) == 2
    end

    test "exports to JSON columns format", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_cols_#{:rand.uniform(100_000)}.json")

      assert :ok = Export.to_json(dataset, path, orient: :columns)

      {:ok, data} = Jason.decode(File.read!(path))
      assert is_map(data)
      assert Map.has_key?(data, "name")
      assert is_list(data["name"])
    end
  end

  describe "to_jsonl/3" do
    test "exports to JSONL format", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_#{:rand.uniform(100_000)}.jsonl")

      assert :ok = Export.to_jsonl(dataset, path)
      assert File.exists?(path)

      lines = path |> File.read!() |> String.split("\n", trim: true)
      assert length(lines) == 2

      assert {:ok, _} = Jason.decode(hd(lines))
    end
  end

  describe "to_parquet/3" do
    test "exports to Parquet format", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_#{:rand.uniform(100_000)}.parquet")

      assert :ok = Export.to_parquet(dataset, path)
      assert File.exists?(path)

      df = Explorer.DataFrame.from_parquet!(path)
      assert Explorer.DataFrame.n_rows(df) == 2
    end
  end

  describe "round-trip" do
    test "CSV round-trip preserves data", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_rt_#{:rand.uniform(100_000)}.csv")

      :ok = Export.to_csv(dataset, path)
      {:ok, loaded} = HfDatasetsEx.Loader.load_from_file(path)

      assert Dataset.num_items(loaded) == Dataset.num_items(dataset)
    end

    test "JSONL round-trip preserves data", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_rt_#{:rand.uniform(100_000)}.jsonl")

      :ok = Export.to_jsonl(dataset, path)
      {:ok, loaded} = HfDatasetsEx.Loader.load_from_file(path)

      assert Dataset.num_items(loaded) == Dataset.num_items(dataset)
    end

    test "Parquet round-trip preserves data", %{dataset: dataset} do
      path = Path.join(@temp_dir, "test_rt_#{:rand.uniform(100_000)}.parquet")

      :ok = Export.to_parquet(dataset, path)
      {:ok, loaded} = HfDatasetsEx.Loader.load_from_file(path)

      assert Dataset.num_items(loaded) == Dataset.num_items(dataset)
    end
  end
end
