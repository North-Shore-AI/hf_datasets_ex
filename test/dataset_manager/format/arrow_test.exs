defmodule HfDatasetsEx.Format.ArrowTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Export
  alias HfDatasetsEx.Format.Arrow

  @fixtures_dir Path.join(System.tmp_dir!(), "arrow_format_test_#{:rand.uniform(100_000)}")

  setup_all do
    File.mkdir_p!(@fixtures_dir)

    # Create Arrow file
    df =
      Explorer.DataFrame.new(%{
        "name" => ["Alice", "Bob", "Charlie"],
        "age" => [30, 25, 35],
        "score" => [95.5, 87.2, 91.8]
      })

    path = Path.join(@fixtures_dir, "test.arrow")
    Explorer.DataFrame.to_ipc(df, path)

    on_exit(fn -> File.rm_rf!(@fixtures_dir) end)

    {:ok, path: path}
  end

  describe "parse/2" do
    test "parses Arrow file", %{path: path} do
      assert {:ok, items} = Arrow.parse(path)
      assert length(items) == 3
      assert hd(items)["name"] == "Alice"
    end

    test "selects specific columns", %{path: path} do
      assert {:ok, items} = Arrow.parse(path, columns: ["name", "age"])

      keys = Map.keys(hd(items))
      assert "name" in keys
      assert "age" in keys
      refute "score" in keys
    end

    test "returns error for missing file" do
      assert {:error, _} = Arrow.parse("/nonexistent.arrow")
    end
  end

  describe "round-trip" do
    test "write and read preserves data" do
      dataset =
        HfDatasetsEx.Dataset.from_list([
          %{"x" => 1, "y" => "a"},
          %{"x" => 2, "y" => "b"}
        ])

      path = Path.join(@fixtures_dir, "roundtrip.arrow")

      assert :ok = Export.Arrow.write(dataset, path)
      assert {:ok, items} = Arrow.parse(path)

      assert length(items) == 2
      assert hd(items)["x"] == 1
    end
  end
end
