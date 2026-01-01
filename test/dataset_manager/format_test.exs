defmodule HfDatasetsEx.FormatTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Format

  describe "Format.JSONL" do
    alias HfDatasetsEx.Format.JSONL

    setup do
      tmp_path = System.tmp_dir!() |> Path.join("test_#{:rand.uniform(100_000)}.jsonl")
      content = ~s|{"id": 1, "text": "hello"}\n{"id": 2, "text": "world"}\n|
      File.write!(tmp_path, content)

      on_exit(fn -> File.rm(tmp_path) end)
      %{path: tmp_path}
    end

    test "parse/1 returns list of maps", %{path: path} do
      {:ok, items} = JSONL.parse(path)

      assert length(items) == 2
      assert hd(items)["id"] == 1
      assert hd(items)["text"] == "hello"
    end

    test "parse_stream/1 returns lazy stream", %{path: path} do
      stream = File.stream!(path, :line)
      result = JSONL.parse_stream(stream) |> Enum.to_list()

      assert length(result) == 2
      assert hd(result)["id"] == 1
    end

    test "handles?/1 returns true for .jsonl files" do
      assert JSONL.handles?("data.jsonl")
      assert JSONL.handles?("path/to/data.jsonlines")
      refute JSONL.handles?("data.json")
      refute JSONL.handles?("data.csv")
    end
  end

  describe "Format.JSON" do
    alias HfDatasetsEx.Format.JSON

    setup do
      tmp_path = System.tmp_dir!() |> Path.join("test_#{:rand.uniform(100_000)}.json")
      content = ~s|[{"id": 1, "text": "hello"}, {"id": 2, "text": "world"}]|
      File.write!(tmp_path, content)

      on_exit(fn -> File.rm(tmp_path) end)
      %{path: tmp_path}
    end

    test "parse/1 returns list of maps from array", %{path: path} do
      {:ok, items} = JSON.parse(path)

      assert length(items) == 2
      assert hd(items)["id"] == 1
    end

    test "parse/1 wraps single object in list" do
      tmp_path = System.tmp_dir!() |> Path.join("single_#{:rand.uniform(100_000)}.json")
      File.write!(tmp_path, ~s|{"id": 1}|)
      on_exit(fn -> File.rm(tmp_path) end)

      {:ok, items} = JSON.parse(tmp_path)
      assert length(items) == 1
      assert hd(items)["id"] == 1
    end

    test "handles?/1 returns true for .json files" do
      assert JSON.handles?("data.json")
      assert JSON.handles?("path/to/config.json")
      refute JSON.handles?("data.jsonl")
    end
  end

  describe "Format.CSV" do
    alias HfDatasetsEx.Format.CSV

    setup do
      tmp_path = System.tmp_dir!() |> Path.join("test_#{:rand.uniform(100_000)}.csv")
      content = "id,text\n1,hello\n2,world\n"
      File.write!(tmp_path, content)

      on_exit(fn -> File.rm(tmp_path) end)
      %{path: tmp_path}
    end

    test "parse/1 returns list of maps with headers as keys", %{path: path} do
      {:ok, items} = CSV.parse(path)

      assert length(items) == 2
      assert hd(items)["id"] == "1"
      assert hd(items)["text"] == "hello"
    end

    test "handles?/1 returns true for .csv files" do
      assert CSV.handles?("data.csv")
      refute CSV.handles?("data.json")
    end
  end

  describe "Format.Parquet" do
    alias HfDatasetsEx.Format.Parquet

    setup do
      tmp_path = System.tmp_dir!() |> Path.join("test_#{:rand.uniform(100_000)}.parquet")

      parquet =
        [
          %{"id" => 1, "value" => "a"},
          %{"id" => 2, "value" => "b"}
        ]
        |> Explorer.DataFrame.new()
        |> Explorer.DataFrame.dump_parquet!()

      File.write!(tmp_path, parquet)

      Application.put_env(:hf_datasets_ex, :parquet_backend, TestSupport.ParquetBackend)

      on_exit(fn ->
        Application.delete_env(:hf_datasets_ex, :parquet_backend)
        File.rm(tmp_path)
      end)

      %{path: tmp_path}
    end

    test "handles?/1 returns true for .parquet files" do
      assert Parquet.handles?("data.parquet")
      refute Parquet.handles?("data.json")
    end

    test "parse/1 uses rechunk for parquet reader", %{path: path} do
      {:ok, items} = Parquet.parse(path)

      assert length(items) == 2
      assert_receive {:from_parquet, ^path, opts}
      assert Keyword.get(opts, :rechunk) == true
    end

    test "stream_rows/2 uses rechunk for parquet reader", %{path: path} do
      Parquet.stream_rows(path, batch_size: 1) |> Enum.to_list()

      assert_receive {:from_parquet, ^path, opts}
      assert Keyword.get(opts, :rechunk) == true
    end
  end

  describe "Format.detect/1" do
    test "detects format from file path" do
      assert {:ok, HfDatasetsEx.Format.JSONL, []} = Format.detect("data.jsonl")
      assert {:ok, HfDatasetsEx.Format.JSONL, []} = Format.detect("data.ndjson")
      assert {:ok, HfDatasetsEx.Format.JSON, []} = Format.detect("data.json")
      assert {:ok, HfDatasetsEx.Format.CSV, []} = Format.detect("data.csv")
      assert {:ok, HfDatasetsEx.Format.CSV, [delimiter: "\t"]} = Format.detect("data.tsv")
      assert {:ok, HfDatasetsEx.Format.Parquet, []} = Format.detect("data.parquet")
      assert {:ok, HfDatasetsEx.Format.Text, []} = Format.detect("data.txt")
      assert {:ok, HfDatasetsEx.Format.Arrow, []} = Format.detect("data.arrow")
      assert {:error, :unknown_format} = Format.detect("data.unknown")
    end
  end

  describe "Format.parser_for/1" do
    test "returns correct parser module" do
      assert Format.parser_for(:jsonl) == HfDatasetsEx.Format.JSONL
      assert Format.parser_for(:json) == HfDatasetsEx.Format.JSON
      assert Format.parser_for(:csv) == HfDatasetsEx.Format.CSV
      assert Format.parser_for(:tsv) == {HfDatasetsEx.Format.CSV, [delimiter: "\t"]}
      assert Format.parser_for(:parquet) == HfDatasetsEx.Format.Parquet
      assert Format.parser_for(:text) == HfDatasetsEx.Format.Text
      assert Format.parser_for(:arrow) == HfDatasetsEx.Format.Arrow
      assert Format.parser_for(:unknown) == nil
    end
  end
end
