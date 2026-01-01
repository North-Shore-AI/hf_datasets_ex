defmodule HfDatasetsEx.Fetcher.HuggingFaceTest do
  use ExUnit.Case, async: false

  alias HfDatasetsEx.Fetcher.HuggingFace

  describe "build_file_url/3" do
    test "builds correct URL for main branch" do
      url = HuggingFace.build_file_url("openai/gsm8k", "data/train.parquet")

      assert url == "https://huggingface.co/datasets/openai/gsm8k/resolve/main/data/train.parquet"
    end

    test "builds correct URL with revision" do
      url =
        HuggingFace.build_file_url(
          "openai/gsm8k",
          "data/train.parquet",
          revision: "abc123"
        )

      assert url ==
               "https://huggingface.co/datasets/openai/gsm8k/resolve/abc123/data/train.parquet"
    end
  end

  @moduletag :live

  describe "list_files/2" do
    test "lists files for a dataset" do
      {:ok, files} = HuggingFace.list_files("openai/gsm8k")

      assert is_list(files)
      assert files != []

      # Should have directories or files
      file_names = Enum.map(files, & &1["path"])
      # GSM8K has main and socratic directories at root level
      assert Enum.any?(
               file_names,
               &(&1 == "main" or &1 == "socratic" or String.contains?(&1, "parquet"))
             )
    end

    test "lists files for a dataset subdirectory" do
      {:ok, files} = HuggingFace.list_files("openai/gsm8k", config: "main")

      assert is_list(files)
      assert files != []

      # Should have parquet files in the main subdirectory
      file_names = Enum.map(files, & &1["path"])
      assert Enum.any?(file_names, &String.ends_with?(&1, ".parquet"))
    end

    test "returns error for non-existent dataset" do
      result = HuggingFace.list_files("nonexistent/dataset12345")

      assert {:error, _reason} = result
    end
  end

  describe "download_file/2" do
    test "downloads a small file" do
      # Use a small, known file from the openai/gsm8k dataset
      # First, get the file list to find a valid file path
      {:ok, files} = HuggingFace.list_files("openai/gsm8k")

      # Find a parquet file
      parquet_file =
        Enum.find(files, fn f ->
          String.ends_with?(f["path"], ".parquet")
        end)

      if parquet_file do
        {:ok, data} =
          HuggingFace.download_file(
            "openai/gsm8k",
            parquet_file["path"]
          )

        assert is_binary(data)
        assert byte_size(data) > 0
      end
    end

    test "returns error for non-existent file" do
      result =
        HuggingFace.download_file(
          "openai/gsm8k",
          "nonexistent/file.txt"
        )

      assert {:error, _reason} = result
    end
  end

  describe "fetch/2" do
    @tag timeout: 120_000
    test "fetches GSM8K train data" do
      {:ok, data} = HuggingFace.fetch("openai/gsm8k", split: "train")

      assert is_list(data)
      # GSM8K has ~7.5K train examples
      assert length(data) > 1000

      first = hd(data)
      assert Map.has_key?(first, "question")
      assert Map.has_key?(first, "answer")
    end

    @tag timeout: 120_000
    test "fetches GSM8K test data" do
      {:ok, data} = HuggingFace.fetch("openai/gsm8k", split: "test")

      assert is_list(data)
      # GSM8K has ~1.3K test examples
      assert length(data) > 1000

      first = hd(data)
      assert Map.has_key?(first, "question")
      assert Map.has_key?(first, "answer")
    end

    @tag timeout: 120_000
    test "fetches data with config" do
      # MMLU has configs/subsets
      {:ok, data} =
        HuggingFace.fetch("cais/mmlu",
          config: "astronomy",
          split: "test"
        )

      assert is_list(data)
      assert data != []

      first = hd(data)
      # MMLU has question and choices columns
      assert Map.has_key?(first, "question") or Map.has_key?(first, "input")
    end

    test "returns error for non-existent dataset" do
      result = HuggingFace.fetch("nonexistent/dataset12345")

      assert {:error, _reason} = result
    end
  end
end
