defmodule HfDatasetsEx.Export.TextTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.{Dataset, Export}

  @fixtures_dir Path.join(System.tmp_dir!(), "text_export_test_#{:rand.uniform(100_000)}")

  setup do
    File.mkdir_p!(@fixtures_dir)
    on_exit(fn -> File.rm_rf!(@fixtures_dir) end)
    :ok
  end

  describe "write/3" do
    test "exports dataset to text file" do
      dataset =
        Dataset.from_list([
          %{"text" => "Hello"},
          %{"text" => "World"}
        ])

      path = Path.join(@fixtures_dir, "out.txt")
      assert :ok = Export.Text.write(dataset, path)

      content = File.read!(path)
      assert content == "Hello\nWorld\n"
    end

    test "uses custom column" do
      dataset =
        Dataset.from_list([
          %{"content" => "Line 1"},
          %{"content" => "Line 2"}
        ])

      path = Path.join(@fixtures_dir, "out.txt")
      assert :ok = Export.Text.write(dataset, path, column: "content")

      content = File.read!(path)
      assert content == "Line 1\nLine 2\n"
    end
  end
end
