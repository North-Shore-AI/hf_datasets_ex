# Type Casting Example
# Demonstrates casting columns to new types and encoding labels

alias HfDatasetsEx.{Dataset, Features}
alias HfDatasetsEx.Features.{Value, ClassLabel}

IO.puts("=== Type Casting Example ===\n")

# Create dataset with string data that needs casting
dataset =
  Dataset.from_list([
    %{"name" => "Alice", "age" => "30", "score" => "95.5", "grade" => "A"},
    %{"name" => "Bob", "age" => "25", "score" => "87.2", "grade" => "B"},
    %{"name" => "Charlie", "age" => "35", "score" => "91.8", "grade" => "A"},
    %{"name" => "Diana", "age" => "28", "score" => "78.3", "grade" => "C"}
  ])

IO.puts("Original dataset:")
IO.puts("  First item: #{inspect(hd(dataset.items))}")
IO.puts("  'age' type: #{if is_binary(hd(dataset.items)["age"]), do: "string", else: "number"}\n")

# Cast entire dataset to new schema
IO.puts("=== Cast to Schema ===")

new_features =
  Features.new(%{
    "name" => %Value{dtype: :string},
    "age" => %Value{dtype: :int32},
    "score" => %Value{dtype: :float32},
    "grade" => ClassLabel.new(names: ["A", "B", "C", "D", "F"])
  })

{:ok, casted} = Dataset.cast(dataset, new_features)
first = hd(casted.items)
IO.puts("After casting:")
IO.puts("  First item: #{inspect(first)}")
IO.puts("  'age' type: #{if is_integer(first["age"]), do: "integer", else: "other"}")
IO.puts("  'score' type: #{if is_float(first["score"]), do: "float", else: "other"}")
IO.puts("  'grade' value: #{first["grade"]} (encoded as integer)")

# Cast single column
IO.puts("\n=== Cast Single Column ===")

dataset2 =
  Dataset.from_list([
    %{"value" => "100", "label" => "positive"},
    %{"value" => "200", "label" => "negative"}
  ])

{:ok, casted2} = Dataset.cast_column(dataset2, "value", %Value{dtype: :int64})
IO.puts("Casted 'value' column to int64:")

IO.puts(
  "  First value: #{hd(casted2.items)["value"]} (#{if is_integer(hd(casted2.items)["value"]), do: "integer", else: "other"})"
)

# Class encode column (auto-infer classes)
IO.puts("\n=== Class Encode Column ===")

text_dataset =
  Dataset.from_list([
    %{"text" => "I love it", "sentiment" => "positive"},
    %{"text" => "It's okay", "sentiment" => "neutral"},
    %{"text" => "I hate it", "sentiment" => "negative"},
    %{"text" => "Great!", "sentiment" => "positive"},
    %{"text" => "Meh", "sentiment" => "neutral"}
  ])

IO.puts("Before encoding:")
IO.puts("  Sentiments: #{inspect(Enum.map(text_dataset.items, & &1["sentiment"]))}")

{:ok, encoded} = Dataset.class_encode_column(text_dataset, "sentiment")
IO.puts("\nAfter encoding:")
IO.puts("  Sentiments: #{inspect(Enum.map(encoded.items, & &1["sentiment"]))}")

# Check the inferred ClassLabel
class_label = encoded.features.schema["sentiment"]
IO.puts("  Class names: #{inspect(class_label.names)}")
IO.puts("  Mapping: negative=0, neutral=1, positive=2")

# Train/test split with stratification
IO.puts("\n=== Stratified Train/Test Split ===")

larger_dataset =
  Dataset.from_list([
    %{"x" => 1, "label" => "A"},
    %{"x" => 2, "label" => "A"},
    %{"x" => 3, "label" => "A"},
    %{"x" => 4, "label" => "A"},
    %{"x" => 5, "label" => "B"},
    %{"x" => 6, "label" => "B"},
    %{"x" => 7, "label" => "A"},
    %{"x" => 8, "label" => "A"},
    %{"x" => 9, "label" => "B"},
    %{"x" => 10, "label" => "B"}
  ])

{:ok, %{train: train, test: test}} =
  Dataset.train_test_split(larger_dataset,
    test_size: 0.3,
    stratify_by_column: "label",
    seed: 42
  )

train_a = Enum.count(train.items, &(&1["label"] == "A"))
train_b = Enum.count(train.items, &(&1["label"] == "B"))
test_a = Enum.count(test.items, &(&1["label"] == "A"))
test_b = Enum.count(test.items, &(&1["label"] == "B"))

IO.puts("Original: 6 A's, 4 B's")
IO.puts("Train set: #{train_a} A's, #{train_b} B's (total: #{Dataset.num_items(train)})")
IO.puts("Test set: #{test_a} A's, #{test_b} B's (total: #{Dataset.num_items(test)})")
IO.puts("Stratification preserved class ratios!")

IO.puts("\n=== Type Casting Example Complete ===")
