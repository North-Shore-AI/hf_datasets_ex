defmodule HfDatasetsEx.Features.ArrayTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Features.{Array2D, Array3D, Array4D, Array5D}

  describe "Array2D" do
    test "new creates correct struct" do
      arr = Array2D.new({28, 28}, :float32)

      assert arr.shape == {28, 28}
      assert arr.dtype == :float32
    end

    test "validate accepts correct nested list" do
      arr = Array2D.new({2, 3}, :float32)
      value = [[1, 2, 3], [4, 5, 6]]

      assert {:ok, ^value} = Array2D.validate(value, arr)
    end

    test "validate rejects wrong shape" do
      arr = Array2D.new({2, 3}, :float32)
      value = [[1, 2], [3, 4]]

      assert {:error, {:shape_mismatch, _}} = Array2D.validate(value, arr)
    end

    test "validate accepts Nx tensor" do
      arr = Array2D.new({2, 3}, :float32)
      tensor = Nx.tensor([[1, 2, 3], [4, 5, 6]])

      assert {:ok, ^tensor} = Array2D.validate(tensor, arr)
    end

    test "to_nx converts list to tensor" do
      arr = Array2D.new({2, 3}, :float32)
      value = [[1, 2, 3], [4, 5, 6]]

      tensor = Array2D.to_nx(value, arr)

      assert Nx.shape(tensor) == {2, 3}
      assert Nx.type(tensor) == {:f, 32}
    end
  end

  describe "Array3D" do
    test "validates 3D tensor" do
      arr = Array3D.new({2, 3, 4}, :float32)
      tensor = Nx.iota({2, 3, 4})

      assert {:ok, ^tensor} = Array3D.validate(tensor, arr)
    end

    test "to_nx creates correct tensor" do
      arr = Array3D.new({2, 2, 2}, :int32)
      value = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]]

      tensor = Array3D.to_nx(value, arr)

      assert Nx.shape(tensor) == {2, 2, 2}
      assert Nx.type(tensor) == {:s, 32}
    end
  end

  describe "Array4D" do
    test "validates 4D tensor" do
      arr = Array4D.new({2, 3, 4, 5}, :float32)
      tensor = Nx.iota({2, 3, 4, 5})

      assert {:ok, ^tensor} = Array4D.validate(tensor, arr)
    end
  end

  describe "Array5D" do
    test "validates 5D tensor" do
      arr = Array5D.new({2, 3, 4, 5, 6}, :float32)
      tensor = Nx.iota({2, 3, 4, 5, 6})

      assert {:ok, ^tensor} = Array5D.validate(tensor, arr)
    end
  end
end
