defmodule HfDatasetsEx.DatasetOpsExtendedTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.{Dataset, Features}
  alias HfDatasetsEx.Features.{ClassLabel, Value}

  describe "cast/2" do
    test "casts column types" do
      dataset =
        Dataset.from_list([
          %{"x" => "1.5", "label" => "pos"},
          %{"x" => "2.5", "label" => "neg"}
        ])

      features =
        Features.new(%{
          "x" => %Value{dtype: :float32},
          "label" => %ClassLabel{names: ["neg", "pos"], num_classes: 2}
        })

      assert {:ok, casted} = Dataset.cast(dataset, features)

      [first | _] = casted.items
      assert is_number(first["x"])
      assert is_integer(first["label"])
    end

    test "returns error for invalid cast" do
      dataset = Dataset.from_list([%{"x" => "not_a_number"}])
      features = Features.new(%{"x" => %Value{dtype: :float32}})

      assert {:error, _} = Dataset.cast(dataset, features)
    end
  end

  describe "cast_column/3" do
    test "casts single column" do
      dataset =
        Dataset.from_list([
          %{"label" => "pos", "text" => "hello"},
          %{"label" => "neg", "text" => "bye"}
        ])

      class_label = %ClassLabel{names: ["neg", "pos"], num_classes: 2}
      assert {:ok, casted} = Dataset.cast_column(dataset, "label", class_label)

      [first | _] = casted.items
      assert first["label"] == 1
      assert first["text"] == "hello"
    end
  end

  describe "class_encode_column/2" do
    test "encodes string column to integers" do
      dataset =
        Dataset.from_list([
          %{"label" => "positive"},
          %{"label" => "negative"},
          %{"label" => "positive"}
        ])

      assert {:ok, encoded} = Dataset.class_encode_column(dataset, "label")

      labels = Enum.map(encoded.items, & &1["label"])
      assert Enum.all?(labels, &is_integer/1)

      assert %ClassLabel{names: names} = encoded.features.schema["label"]
      assert "negative" in names
      assert "positive" in names
    end

    test "preserves nil values by default" do
      dataset =
        Dataset.from_list([
          %{"label" => "a"},
          %{"label" => nil},
          %{"label" => "b"}
        ])

      assert {:ok, encoded} = Dataset.class_encode_column(dataset, "label")

      [_, second, _] = encoded.items
      assert is_nil(second["label"])
    end
  end

  describe "train_test_split/2" do
    test "splits with fraction" do
      dataset = Dataset.from_list(Enum.map(1..100, &%{"x" => &1}))

      assert {:ok, %{train: train, test: test}} =
               Dataset.train_test_split(dataset, test_size: 0.2, shuffle: false)

      assert Dataset.num_items(train) == 80
      assert Dataset.num_items(test) == 20
    end

    test "stratified split maintains class distribution" do
      items =
        [
          Enum.map(1..80, &%{"x" => &1, "label" => "pos"}),
          Enum.map(1..20, &%{"x" => &1, "label" => "neg"})
        ]
        |> List.flatten()

      dataset = Dataset.from_list(items)

      assert {:ok, %{train: train, test: test}} =
               Dataset.train_test_split(dataset,
                 test_size: 0.2,
                 stratify_by_column: "label",
                 shuffle: false
               )

      train_pos = Enum.count(train.items, &(&1["label"] == "pos"))
      train_neg = Enum.count(train.items, &(&1["label"] == "neg"))

      assert_in_delta train_pos / Dataset.num_items(train), 0.8, 0.1
      assert_in_delta train_neg / Dataset.num_items(train), 0.2, 0.1
      assert Dataset.num_items(test) == 20
    end

    test "respects seed for reproducibility" do
      dataset = Dataset.from_list(Enum.map(1..100, &%{"x" => &1}))

      {:ok, split1} = Dataset.train_test_split(dataset, test_size: 0.2, seed: 42)
      {:ok, split2} = Dataset.train_test_split(dataset, test_size: 0.2, seed: 42)

      assert split1.train.items == split2.train.items
    end
  end

  describe "to_dict/2" do
    test "converts to column-oriented dict" do
      dataset =
        Dataset.from_list([
          %{"name" => "Alice", "age" => 30},
          %{"name" => "Bob", "age" => 25}
        ])

      dict = Dataset.to_dict(dataset)

      assert dict["name"] == ["Alice", "Bob"]
      assert dict["age"] == [30, 25]
    end

    test "handles empty dataset" do
      dataset = Dataset.from_list([])
      assert Dataset.to_dict(dataset) == %{}
    end

    test "respects :columns option" do
      dataset =
        Dataset.from_list([
          %{"a" => 1, "b" => 2, "c" => 3}
        ])

      dict = Dataset.to_dict(dataset, columns: ["a", "c"])

      assert Map.keys(dict) == ["a", "c"]
    end
  end
end
