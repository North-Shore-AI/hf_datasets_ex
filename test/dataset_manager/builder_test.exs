defmodule HfDatasetsEx.BuilderTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.{Builder, Dataset, DatasetDict, DatasetInfo, Features}
  alias HfDatasetsEx.Features.Value

  # Test builder module
  defmodule TestDataset do
    use HfDatasetsEx.DatasetBuilder

    @impl true
    def info do
      DatasetInfo.new(
        description: "Test dataset",
        features: Features.new(%{"x" => %Value{dtype: :int32}})
      )
    end

    @impl true
    def split_generators(_dm, _config) do
      [
        SplitGenerator.new(:train, %{data: [1, 2, 3]}),
        SplitGenerator.new(:test, %{data: [4, 5]})
      ]
    end

    @impl true
    def generate_examples(%{data: data}, _split) do
      data
      |> Enum.with_index()
      |> Enum.map(fn {x, idx} -> {idx, %{"x" => x}} end)
    end
  end

  defmodule MultiConfigDataset do
    use HfDatasetsEx.DatasetBuilder

    @impl true
    def info, do: DatasetInfo.new()

    @impl true
    def configs do
      [
        BuilderConfig.new(name: "small"),
        BuilderConfig.new(name: "large")
      ]
    end

    @impl true
    def default_config_name, do: "small"

    @impl true
    def split_generators(_dm, %{name: "small"}) do
      [SplitGenerator.new(:train, %{data: [1, 2]})]
    end

    def split_generators(_dm, %{name: "large"}) do
      [SplitGenerator.new(:train, %{data: [1, 2, 3, 4, 5]})]
    end

    @impl true
    def generate_examples(%{data: data}, _split) do
      Enum.map(data, &%{"x" => &1})
    end
  end

  describe "Builder.build/2" do
    test "builds DatasetDict with all splits" do
      assert {:ok, %DatasetDict{} = dd} = Builder.build(TestDataset)

      assert DatasetDict.split_names(dd) == ["test", "train"]
      assert Dataset.num_items(dd.datasets["train"]) == 3
      assert Dataset.num_items(dd.datasets["test"]) == 2
    end

    test "builds single split when specified" do
      assert {:ok, %Dataset{} = ds} = Builder.build(TestDataset, split: :train)

      assert Dataset.num_items(ds) == 3
    end

    test "uses default config" do
      assert {:ok, %DatasetDict{} = dd} = Builder.build(MultiConfigDataset)

      train = dd.datasets["train"]
      assert Dataset.num_items(train) == 2
    end

    test "uses specified config" do
      assert {:ok, %DatasetDict{} = dd} = Builder.build(MultiConfigDataset, config_name: "large")

      train = dd.datasets["train"]
      assert Dataset.num_items(train) == 5
    end

    test "returns error for unknown config" do
      assert {:error, {:unknown_config, "nonexistent", _}} =
               Builder.build(MultiConfigDataset, config_name: "nonexistent")
    end

    test "preserves info in dataset" do
      {:ok, dd} = Builder.build(TestDataset)

      train = dd.datasets["train"]
      assert train.features != nil
      assert train.metadata.description == "Test dataset"
    end
  end
end

defmodule HfDatasetsEx.DownloadManagerTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.DownloadManager

  @temp_dir Path.join(System.tmp_dir!(), "dm_test_#{:rand.uniform(100_000)}")

  setup do
    File.mkdir_p!(@temp_dir)
    on_exit(fn -> File.rm_rf!(@temp_dir) end)
    {:ok, dm: DownloadManager.new(cache_dir: @temp_dir)}
  end

  describe "download/2" do
    @tag :network
    test "downloads file", %{dm: dm} do
      # Use a small known file
      url = "https://raw.githubusercontent.com/huggingface/datasets/main/README.md"

      assert {:ok, path} = DownloadManager.download(dm, url)
      assert File.exists?(path)
    end

    test "caches downloads", %{dm: dm} do
      # Create a fake cached file
      hash =
        :crypto.hash(:sha256, "http://example.com/file.txt")
        |> Base.encode16(case: :lower)
        |> String.slice(0, 16)

      cache_path = Path.join(@temp_dir, "#{hash}.txt")
      File.write!(cache_path, "cached content")

      assert {:ok, ^cache_path} = DownloadManager.download(dm, "http://example.com/file.txt")
    end
  end

  describe "download_and_extract/2" do
    test "extracts tar.gz", %{dm: dm} do
      # Create test archive
      archive_path = Path.join(@temp_dir, "test.tar.gz")
      _extract_dir = archive_path <> "_extracted"

      # Create simple tar.gz
      File.mkdir_p!(Path.join(@temp_dir, "test_content"))
      File.write!(Path.join(@temp_dir, "test_content/file.txt"), "hello")

      System.cmd("tar", ["-czf", archive_path, "-C", @temp_dir, "test_content"])

      # Mock the download by creating the cached file
      hash =
        :crypto.hash(:sha256, "http://example.com/test.tar.gz")
        |> Base.encode16(case: :lower)
        |> String.slice(0, 16)

      cached_path = Path.join(@temp_dir, "#{hash}.tar.gz")
      File.copy!(archive_path, cached_path)

      assert {:ok, dir} =
               DownloadManager.download_and_extract(dm, "http://example.com/test.tar.gz")

      assert File.exists?(Path.join(dir, "test_content/file.txt"))
    end
  end
end
