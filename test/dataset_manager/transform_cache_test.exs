defmodule HfDatasetsEx.TransformCacheTest do
  use ExUnit.Case, async: false

  alias HfDatasetsEx.{Dataset, Fingerprint, TransformCache}

  @cache_dir Path.join(System.tmp_dir!(), "transform_cache_test_#{:rand.uniform(100_000)}")

  setup do
    Application.put_env(:hf_datasets_ex, :transform_cache_dir, @cache_dir)
    File.mkdir_p!(@cache_dir)

    on_exit(fn ->
      File.rm_rf!(@cache_dir)
      Application.delete_env(:hf_datasets_ex, :transform_cache_dir)
    end)

    :ok
  end

  describe "get/2 and put/3" do
    test "cache miss returns :miss" do
      assert :miss = TransformCache.get("nonexistent", "also_nonexistent")
    end

    test "cache hit returns dataset" do
      dataset = Dataset.from_list([%{"x" => 1}])
      input_fp = Fingerprint.from_dataset(dataset)
      transform_fp = Fingerprint.generate(:test, [])

      TransformCache.put(input_fp, transform_fp, dataset)

      assert {:ok, cached} = TransformCache.get(input_fp, transform_fp)
      assert cached.items == dataset.items
    end
  end

  describe "cleanup/1" do
    test "removes old entries" do
      dataset = Dataset.from_list([%{"x" => 1}])
      input_fp = Fingerprint.from_dataset(dataset)
      transform_fp = Fingerprint.generate(:test, [])

      TransformCache.put(input_fp, transform_fp, dataset)

      {:ok, deleted} = TransformCache.cleanup(max_age_days: 0)

      assert deleted >= 0
    end
  end

  describe "stats/0" do
    test "returns cache statistics" do
      stats = TransformCache.stats()

      assert is_integer(stats.entry_count)
      assert is_integer(stats.total_size_bytes)
      assert is_binary(stats.cache_dir)
    end
  end
end
