defmodule HfDatasetsEx.Loader.VisionTest do
  use TestSupport.HfCase

  alias HfDatasetsEx.{Dataset, Features}
  alias HfDatasetsEx.Loader.Vision

  test "loads caltech101 dataset" do
    {:ok, dataset} = Vision.load(:caltech101, sample_size: 2)

    assert %Dataset{} = dataset
    assert dataset.name == "caltech101"
    assert length(dataset.items) == 2
    assert %Features{} = dataset.features

    first = hd(dataset.items)
    assert is_map(first.input.image)
    assert is_binary(first.input.image["bytes"])
  end

  test "returns error for unknown dataset" do
    assert {:error, {:unknown_vision_dataset, :unknown}} = Vision.load(:unknown)
  end
end
