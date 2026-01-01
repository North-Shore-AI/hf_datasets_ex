# Implementation Prompt: Missing Dataset Operations

## Priority: P1 (High)

## Objective

Implement missing dataset transformation methods: `cast/2`, `cast_column/3`, `class_encode_column/2`, `train_test_split/2` with stratify, and `to_dict/2`.

## Required Reading

Before starting, read these files completely:

```
lib/dataset_manager/dataset.ex
lib/dataset_manager/features.ex
lib/dataset_manager/features/value.ex
lib/dataset_manager/features/class_label.ex
lib/dataset_manager/sampler.ex
docs/20251231/gap_analysis/01_core_dataset_methods.md
```

## Context

The Elixir port has basic operations (map, filter, shuffle, select, etc.) but is missing several important transformation methods from Python's `datasets`:

- `cast(features)` - Change the schema/types of columns
- `cast_column(column, feature)` - Cast a single column
- `class_encode_column(column)` - Convert string column to ClassLabel
- `train_test_split(test_size, stratify_by_column)` - Split with stratification
- `to_dict()` - Convert to column-oriented dict

## Implementation Requirements

### 1. cast/2

```elixir
@doc """
Cast the dataset to a new feature schema.

## Examples

    new_features = Features.new(%{
      "label" => %ClassLabel{names: ["neg", "pos"]},
      "score" => %Value{dtype: :float32}
    })

    {:ok, casted} = Dataset.cast(dataset, new_features)

"""
@spec cast(t(), Features.t()) :: {:ok, t()} | {:error, term()}
def cast(%__MODULE__{} = dataset, %Features{} = new_features) do
  with {:ok, casted_items} <- cast_items(dataset.items, new_features) do
    {:ok, %{dataset | items: casted_items, features: new_features}}
  end
end

defp cast_items(items, features) do
  try do
    casted = Enum.map(items, &cast_item(&1, features))
    {:ok, casted}
  rescue
    e -> {:error, e}
  end
end

defp cast_item(item, %Features{schema: schema}) do
  Map.new(item, fn {key, value} ->
    case Map.get(schema, key) do
      nil -> {key, value}
      feature -> {key, cast_value(value, feature)}
    end
  end)
end

defp cast_value(value, %Features.Value{dtype: dtype}) do
  Features.Value.cast(value, dtype)
end

defp cast_value(value, %Features.ClassLabel{names: names}) do
  cond do
    is_integer(value) -> value
    is_binary(value) ->
      case Enum.find_index(names, &(&1 == value)) do
        nil -> raise "Unknown class label: #{value}"
        idx -> idx
      end
  end
end

defp cast_value(value, %Features.Sequence{feature: inner_feature}) do
  Enum.map(value, &cast_value(&1, inner_feature))
end

defp cast_value(value, _feature), do: value
```

### 2. cast_column/3

```elixir
@doc """
Cast a single column to a new feature type.

## Examples

    dataset = Dataset.cast_column(dataset, "label", %ClassLabel{names: ["neg", "pos"]})

"""
@spec cast_column(t(), String.t(), Features.feature_type()) :: {:ok, t()} | {:error, term()}
def cast_column(%__MODULE__{} = dataset, column_name, new_feature) do
  try do
    new_items = Enum.map(dataset.items, fn item ->
      case Map.get(item, column_name) do
        nil -> item
        value -> Map.put(item, column_name, cast_value(value, new_feature))
      end
    end)

    new_features = if dataset.features do
      Features.put(dataset.features, column_name, new_feature)
    else
      nil
    end

    {:ok, %{dataset | items: new_items, features: new_features}}
  rescue
    e -> {:error, e}
  end
end
```

### 3. class_encode_column/2

```elixir
@doc """
Convert a string column to ClassLabel encoding.

Automatically infers class names from unique values.

## Options

  * `:include_nulls` - Include nil as a class (default: false)

## Examples

    # Column "sentiment" has values ["positive", "negative", "neutral"]
    {:ok, encoded} = Dataset.class_encode_column(dataset, "sentiment")
    # Now "sentiment" contains integers 0, 1, 2

"""
@spec class_encode_column(t(), String.t(), keyword()) :: {:ok, t()} | {:error, term()}
def class_encode_column(%__MODULE__{} = dataset, column_name, opts \\ []) do
  include_nulls = Keyword.get(opts, :include_nulls, false)

  # Get unique values
  unique_values =
    dataset.items
    |> Enum.map(&Map.get(&1, column_name))
    |> Enum.uniq()
    |> Enum.reject(fn v -> not include_nulls and is_nil(v) end)
    |> Enum.sort()

  # Create ClassLabel feature
  class_label = %Features.ClassLabel{names: unique_values}

  # Create encoding map
  encoding = unique_values |> Enum.with_index() |> Map.new()

  # Encode column
  new_items = Enum.map(dataset.items, fn item ->
    case Map.get(item, column_name) do
      nil -> item
      value -> Map.put(item, column_name, Map.get(encoding, value))
    end
  end)

  # Update features
  new_features = if dataset.features do
    Features.put(dataset.features, column_name, class_label)
  else
    Features.new(%{column_name => class_label})
  end

  {:ok, %{dataset | items: new_items, features: new_features}}
end
```

### 4. train_test_split/2 with Stratify

Update existing `split/2` or add new function:

```elixir
@doc """
Split dataset into train and test sets with optional stratification.

## Options

  * `:test_size` - Fraction or count for test set (default: 0.25)
  * `:train_size` - Fraction or count for train set (optional)
  * `:stratify_by_column` - Column to stratify by (optional)
  * `:seed` - Random seed (optional)
  * `:shuffle` - Shuffle before split (default: true)

## Examples

    # Basic split
    {:ok, %{train: train, test: test}} = Dataset.train_test_split(dataset, test_size: 0.2)

    # Stratified split (maintains class distribution)
    {:ok, splits} = Dataset.train_test_split(dataset,
      test_size: 0.2,
      stratify_by_column: "label"
    )

"""
@spec train_test_split(t(), keyword()) :: {:ok, %{train: t(), test: t()}} | {:error, term()}
def train_test_split(%__MODULE__{} = dataset, opts \\ []) do
  test_size = Keyword.get(opts, :test_size, 0.25)
  seed = Keyword.get(opts, :seed)
  stratify_col = Keyword.get(opts, :stratify_by_column)
  shuffle = Keyword.get(opts, :shuffle, true)

  dataset = if shuffle do
    shuffle(dataset, seed: seed)
  else
    dataset
  end

  if stratify_col do
    stratified_split(dataset, test_size, stratify_col)
  else
    simple_split(dataset, test_size)
  end
end

defp simple_split(%__MODULE__{items: items} = dataset, test_size) do
  n = length(items)
  test_n = if is_float(test_size), do: round(n * test_size), else: test_size
  train_n = n - test_n

  {train_items, test_items} = Enum.split(items, train_n)

  {:ok, %{
    train: %{dataset | items: train_items},
    test: %{dataset | items: test_items}
  }}
end

defp stratified_split(%__MODULE__{items: items} = dataset, test_size, column) do
  # Group by class
  grouped = Enum.group_by(items, &Map.get(&1, column))

  # Split each group
  {train_items, test_items} =
    grouped
    |> Enum.map(fn {_class, class_items} ->
      n = length(class_items)
      test_n = if is_float(test_size), do: round(n * test_size), else: round(n * test_size / length(items))
      Enum.split(class_items, n - test_n)
    end)
    |> Enum.reduce({[], []}, fn {train, test}, {acc_train, acc_test} ->
      {acc_train ++ train, acc_test ++ test}
    end)

  {:ok, %{
    train: %{dataset | items: train_items},
    test: %{dataset | items: test_items}
  }}
end
```

### 5. to_dict/2

```elixir
@doc """
Convert dataset to a column-oriented dictionary.

## Options

  * `:columns` - Specific columns to include (default: all)

## Examples

    dict = Dataset.to_dict(dataset)
    # %{"name" => ["Alice", "Bob"], "age" => [30, 25]}

"""
@spec to_dict(t(), keyword()) :: map()
def to_dict(%__MODULE__{items: items}, opts \\ []) do
  columns = Keyword.get(opts, :columns)

  if items == [] do
    %{}
  else
    keys = if columns, do: columns, else: Map.keys(hd(items))

    Map.new(keys, fn key ->
      {key, Enum.map(items, &Map.get(&1, key))}
    end)
  end
end
```

## TDD Approach

### Step 1: Write Tests First

Create `test/dataset_manager/dataset_ops_extended_test.exs`:

```elixir
defmodule HfDatasetsEx.DatasetOpsExtendedTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.{Dataset, Features}
  alias HfDatasetsEx.Features.{Value, ClassLabel}

  describe "cast/2" do
    test "casts column types" do
      dataset = Dataset.from_list([
        %{"x" => "1.5", "label" => "pos"},
        %{"x" => "2.5", "label" => "neg"}
      ])

      features = Features.new(%{
        "x" => %Value{dtype: :float32},
        "label" => %ClassLabel{names: ["neg", "pos"]}
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
      dataset = Dataset.from_list([
        %{"label" => "pos", "text" => "hello"},
        %{"label" => "neg", "text" => "bye"}
      ])

      class_label = %ClassLabel{names: ["neg", "pos"]}
      assert {:ok, casted} = Dataset.cast_column(dataset, "label", class_label)

      [first | _] = casted.items
      assert first["label"] == 1  # "pos" is index 1
      assert first["text"] == "hello"  # unchanged
    end
  end

  describe "class_encode_column/2" do
    test "encodes string column to integers" do
      dataset = Dataset.from_list([
        %{"label" => "positive"},
        %{"label" => "negative"},
        %{"label" => "positive"}
      ])

      assert {:ok, encoded} = Dataset.class_encode_column(dataset, "label")

      labels = Enum.map(encoded.items, & &1["label"])
      assert Enum.all?(labels, &is_integer/1)

      # Check feature was updated
      assert %ClassLabel{names: names} = encoded.features.schema["label"]
      assert "negative" in names
      assert "positive" in names
    end

    test "preserves nil values by default" do
      dataset = Dataset.from_list([
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
      items = [
        # 80 positive, 20 negative
        Enum.map(1..80, &%{"x" => &1, "label" => "pos"}),
        Enum.map(1..20, &%{"x" => &1, "label" => "neg"})
      ] |> List.flatten()

      dataset = Dataset.from_list(items)

      assert {:ok, %{train: train, test: test}} =
        Dataset.train_test_split(dataset,
          test_size: 0.2,
          stratify_by_column: "label",
          shuffle: false
        )

      # Both splits should have ~80% positive, ~20% negative
      train_pos = Enum.count(train.items, &(&1["label"] == "pos"))
      train_neg = Enum.count(train.items, &(&1["label"] == "neg"))

      assert_in_delta train_pos / Dataset.num_items(train), 0.8, 0.1
      assert_in_delta train_neg / Dataset.num_items(train), 0.2, 0.1
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
      dataset = Dataset.from_list([
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
      dataset = Dataset.from_list([
        %{"a" => 1, "b" => 2, "c" => 3}
      ])

      dict = Dataset.to_dict(dataset, columns: ["a", "c"])

      assert Map.keys(dict) == ["a", "c"]
    end
  end
end
```

### Step 2: Run Tests (They Should Fail)

```bash
mix test test/dataset_manager/dataset_ops_extended_test.exs
```

### Step 3: Implement Until Tests Pass

### Step 4: Quality Checks

```bash
mix format
mix credo --strict
mix dialyzer
mix test
```

## Acceptance Criteria

- [ ] All tests pass
- [ ] `mix format` produces no changes
- [ ] `mix credo --strict` reports no issues
- [ ] `mix dialyzer` reports no errors
- [ ] `mix compile --warnings-as-errors` succeeds
- [ ] Stratified split maintains class proportions
- [ ] class_encode_column updates Features

## Files to Modify

| File | Action |
|------|--------|
| `lib/dataset_manager/dataset.ex` | Add new functions |
| `lib/dataset_manager/features.ex` | Add put/3 if needed |
| `lib/dataset_manager/features/value.ex` | Add cast/2 if needed |
| `test/dataset_manager/dataset_ops_extended_test.exs` | Create |

## Edge Cases to Handle

1. Empty dataset
2. Column doesn't exist
3. Invalid type conversions
4. Stratify column with very rare classes
5. test_size > 1.0 or < 0
6. Features schema is nil
