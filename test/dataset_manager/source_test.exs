defmodule HfDatasetsEx.SourceTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Source.Local

  describe "Source.Local" do
    setup do
      # Create temp directory with test files
      tmp_dir = System.tmp_dir!() |> Path.join("hf_datasets_ex_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      # Create test files
      jsonl_path = Path.join(tmp_dir, "data.jsonl")
      File.write!(jsonl_path, ~s|{"id": 1, "text": "hello"}\n{"id": 2, "text": "world"}\n|)

      json_path = Path.join(tmp_dir, "config.json")
      File.write!(json_path, ~s|{"name": "test"}|)

      csv_path = Path.join(tmp_dir, "data.csv")
      File.write!(csv_path, "id,text\n1,hello\n2,world\n")

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      %{tmp_dir: tmp_dir, jsonl_path: jsonl_path, json_path: json_path, csv_path: csv_path}
    end

    test "list_files/2 returns files in directory", %{tmp_dir: tmp_dir} do
      {:ok, files} = Local.list_files(tmp_dir, [])

      assert length(files) == 3
      assert Enum.all?(files, &Map.has_key?(&1, :path))
      assert Enum.all?(files, &Map.has_key?(&1, :format))
    end

    test "list_files/2 returns single file info for file path", %{jsonl_path: jsonl_path} do
      {:ok, files} = Local.list_files(jsonl_path, [])

      assert length(files) == 1
      assert hd(files).path == jsonl_path
      assert hd(files).format == :jsonl
    end

    test "list_files/2 detects formats correctly", %{tmp_dir: tmp_dir} do
      {:ok, files} = Local.list_files(tmp_dir, [])

      formats = Enum.map(files, & &1.format) |> Enum.sort()
      assert :csv in formats
      assert :json in formats
      assert :jsonl in formats
    end

    test "download/3 returns the same path for local files", %{jsonl_path: jsonl_path} do
      {:ok, path} = Local.download(jsonl_path, "data.jsonl", [])
      assert path == jsonl_path
    end

    test "stream/3 returns a stream for the file", %{jsonl_path: jsonl_path} do
      {:ok, stream} = Local.stream(jsonl_path, "data.jsonl", [])
      lines = Enum.to_list(stream)
      assert length(lines) == 2
    end

    test "exists?/2 returns true for existing path", %{tmp_dir: tmp_dir} do
      assert Local.exists?(tmp_dir, [])
    end

    test "exists?/2 returns false for non-existing path" do
      refute Local.exists?("/nonexistent/path/#{:rand.uniform(100_000)}", [])
    end

    test "list_files/2 returns error for non-existing path" do
      assert {:error, :not_found} = Local.list_files("/nonexistent/path", [])
    end
  end

  describe "Source.HuggingFace" do
    alias HfDatasetsEx.Source.HuggingFace

    @moduletag :live

    @tag timeout: 60_000
    test "list_files/2 returns files for valid repo" do
      {:ok, files} = HuggingFace.list_files("openai/gsm8k", split: "test", config: "main")
      assert is_list(files)
      assert length(files) > 0
    end

    @tag timeout: 60_000
    test "exists?/2 returns true for valid repo" do
      assert HuggingFace.exists?("openai/gsm8k", [])
    end

    test "exists?/2 returns false for invalid repo" do
      refute HuggingFace.exists?("nonexistent/repo_#{:rand.uniform(100_000)}", [])
    end
  end
end
