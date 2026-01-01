defmodule HfDatasetsEx.FormatterTest do
  use ExUnit.Case, async: true
  require Nx

  alias HfDatasetsEx.{Dataset, Formatter}

  describe "Formatter.Nx" do
    test "format_row converts numbers to tensors" do
      row = %{"x" => 1.0, "y" => 2.0}
      formatted = Formatter.Nx.format_row(row)

      assert Nx.is_tensor(formatted["x"])
      assert Nx.to_number(formatted["x"]) == 1.0
    end

    test "format_row preserves strings" do
      row = %{"text" => "hello", "x" => 1.0}
      formatted = Formatter.Nx.format_row(row)

      assert formatted["text"] == "hello"
      assert Nx.is_tensor(formatted["x"])
    end

    test "format_row converts lists of numbers" do
      row = %{"embedding" => [1.0, 2.0, 3.0]}
      formatted = Formatter.Nx.format_row(row)

      assert Nx.is_tensor(formatted["embedding"])
      assert Nx.shape(formatted["embedding"]) == {3}
    end

    test "format_row respects :columns option" do
      row = %{"x" => 1.0, "y" => 2.0, "z" => 3.0}
      formatted = Formatter.Nx.format_row(row, columns: ["x", "y"])

      assert Map.keys(formatted) == ["x", "y"]
    end

    test "format_row respects :dtype option" do
      row = %{"x" => 1}
      formatted = Formatter.Nx.format_row(row, dtype: :float32)

      assert Nx.type(formatted["x"]) == {:f, 32}
    end

    test "format_batch stacks scalars into 1D tensor" do
      rows = [
        %{"x" => 1.0},
        %{"x" => 2.0},
        %{"x" => 3.0}
      ]

      formatted = Formatter.Nx.format_batch(rows)

      assert Nx.is_tensor(formatted["x"])
      assert Nx.shape(formatted["x"]) == {3}
    end

    test "format_batch stacks lists into 2D tensor" do
      rows = [
        %{"embedding" => [1.0, 2.0]},
        %{"embedding" => [3.0, 4.0]}
      ]

      formatted = Formatter.Nx.format_batch(rows)

      assert Nx.is_tensor(formatted["embedding"])
      assert Nx.shape(formatted["embedding"]) == {2, 2}
    end

    test "format_batch handles mixed types" do
      rows = [
        %{"text" => "hello", "x" => 1.0},
        %{"text" => "world", "x" => 2.0}
      ]

      formatted = Formatter.Nx.format_batch(rows)

      assert formatted["text"] == ["hello", "world"]
      assert Nx.is_tensor(formatted["x"])
    end

    test "format_batch handles empty list" do
      assert Formatter.Nx.format_batch([]) == %{}
    end
  end

  describe "Dataset with Nx format" do
    test "set_format changes iteration output" do
      dataset =
        Dataset.from_list([
          %{"x" => 1.0, "y" => 2.0},
          %{"x" => 3.0, "y" => 4.0}
        ])

      formatted = Dataset.set_format(dataset, :nx)

      [first | _] = Enum.to_list(formatted)

      assert Nx.is_tensor(first["x"])
    end

    test "iter returns batched tensors" do
      dataset =
        1..10
        |> Enum.map(&%{"x" => &1 * 1.0})
        |> Dataset.from_list()
        |> Dataset.set_format(:nx)

      batches = dataset |> Dataset.iter(batch_size: 3) |> Enum.to_list()

      assert length(batches) == 4

      [first | _] = batches
      assert Nx.shape(first["x"]) == {3}
    end

    test "iter with drop_last discards incomplete batches" do
      dataset =
        1..10
        |> Enum.map(&%{"x" => &1 * 1.0})
        |> Dataset.from_list()
        |> Dataset.set_format(:nx)

      batches = dataset |> Dataset.iter(batch_size: 3, drop_last: true) |> Enum.to_list()

      assert length(batches) == 3
    end

    test "with_format returns new dataset without modifying original" do
      original = Dataset.from_list([%{"x" => 1.0}])

      formatted = Dataset.with_format(original, :nx)

      assert original.format == :elixir
      assert formatted.format == :nx
    end

    test "reset_format returns to default" do
      dataset =
        Dataset.from_list([%{"x" => 1.0}])
        |> Dataset.set_format(:nx)
        |> Dataset.reset_format()

      assert dataset.format == :elixir
    end
  end

  describe "dtype_to_nx/1" do
    test "maps feature types to Nx types" do
      assert Formatter.Nx.dtype_to_nx(:int32) == {:s, 32}
      assert Formatter.Nx.dtype_to_nx(:float32) == {:f, 32}
      assert Formatter.Nx.dtype_to_nx(:uint8) == {:u, 8}
    end
  end
end
