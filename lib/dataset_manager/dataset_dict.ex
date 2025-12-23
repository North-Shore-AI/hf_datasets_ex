defmodule HfDatasetsEx.DatasetDict do
  @moduledoc """
  A dictionary of Dataset splits.

  DatasetDict provides a convenient way to work with multiple splits of a dataset
  (e.g., train, test, validation) as a single unit. It supports Python-like
  bracket access and provides operations that work across all splits.

  ## Example

      # Create from splits
      dataset_dict = DatasetDict.new(%{
        "train" => train_dataset,
        "test" => test_dataset
      })

      # Access splits
      train = dataset_dict["train"]

      # Apply operations to all splits
      processed = DatasetDict.map(dataset_dict, fn ds ->
        Dataset.filter(ds, &(&1.score > 0.5))
      end)

  """

  alias HfDatasetsEx.Dataset

  @type split_name :: String.t()
  @type t :: %__MODULE__{
          splits: MapSet.t(split_name()),
          datasets: %{split_name() => Dataset.t()}
        }

  @enforce_keys [:splits, :datasets]
  defstruct [:splits, :datasets]

  @doc """
  Create a new DatasetDict from a map of splits.

  Keys can be strings or atoms.

  ## Example

      DatasetDict.new(%{"train" => train, "test" => test})
      DatasetDict.new(%{train: train, test: test})

  """
  @spec new(%{(String.t() | atom()) => Dataset.t()}) :: t()
  def new(datasets_map) when is_map(datasets_map) do
    normalized =
      Map.new(datasets_map, fn {k, v} ->
        key = if is_atom(k), do: Atom.to_string(k), else: k
        {key, v}
      end)

    %__MODULE__{
      splits: MapSet.new(Map.keys(normalized)),
      datasets: normalized
    }
  end

  @doc """
  Create a DatasetDict from a keyword list.

  ## Example

      DatasetDict.from_splits(train: train_dataset, test: test_dataset)

  """
  @spec from_splits(keyword(Dataset.t())) :: t()
  def from_splits(splits) when is_list(splits) do
    new(Map.new(splits))
  end

  @doc """
  Get a split by name.

  ## Example

      train = DatasetDict.get(dd, "train")
      train = DatasetDict.get(dd, :train)

  """
  @spec get(t(), String.t() | atom()) :: Dataset.t() | nil
  def get(%__MODULE__{datasets: datasets}, name) when is_atom(name) do
    Map.get(datasets, Atom.to_string(name))
  end

  def get(%__MODULE__{datasets: datasets}, name) when is_binary(name) do
    Map.get(datasets, name)
  end

  @doc """
  Get all split names.

  ## Example

      names = DatasetDict.split_names(dd)
      # => ["train", "test", "validation"]

  """
  @spec split_names(t()) :: [String.t()]
  def split_names(%__MODULE__{splits: splits}) do
    MapSet.to_list(splits)
  end

  @doc """
  Get the number of splits.
  """
  @spec num_splits(t()) :: non_neg_integer()
  def num_splits(%__MODULE__{splits: splits}) do
    MapSet.size(splits)
  end

  @doc """
  Add or replace a split.

  ## Example

      updated = DatasetDict.put(dd, "validation", validation_dataset)

  """
  @spec put(t(), String.t() | atom(), Dataset.t()) :: t()
  def put(%__MODULE__{splits: splits, datasets: datasets}, name, dataset) do
    key = normalize_key(name)

    %__MODULE__{
      splits: MapSet.put(splits, key),
      datasets: Map.put(datasets, key, dataset)
    }
  end

  @doc """
  Remove a split.

  ## Example

      updated = DatasetDict.delete(dd, "validation")

  """
  @spec delete(t(), String.t() | atom()) :: t()
  def delete(%__MODULE__{splits: splits, datasets: datasets}, name) do
    key = normalize_key(name)

    %__MODULE__{
      splits: MapSet.delete(splits, key),
      datasets: Map.delete(datasets, key)
    }
  end

  @doc """
  Apply a function to all splits.

  The function receives a Dataset and should return a Dataset.

  ## Example

      # Add index to all items in all splits
      result = DatasetDict.map(dd, fn dataset ->
        Dataset.add_column(dataset, :idx, fn _, i -> i end)
      end)

  """
  @spec map(t(), (Dataset.t() -> Dataset.t())) :: t()
  def map(%__MODULE__{splits: splits, datasets: datasets}, fun) when is_function(fun, 1) do
    new_datasets = Map.new(datasets, fn {name, dataset} -> {name, fun.(dataset)} end)

    %__MODULE__{
      splits: splits,
      datasets: new_datasets
    }
  end

  @doc """
  Filter items in all splits.

  ## Example

      # Keep only items with score > 0.5 in all splits
      result = DatasetDict.filter(dd, fn item -> item.score > 0.5 end)

  """
  @spec filter(t(), (map() -> boolean())) :: t()
  def filter(%__MODULE__{} = dd, fun) when is_function(fun, 1) do
    map(dd, fn dataset -> Dataset.filter(dataset, fun) end)
  end

  @doc """
  Select columns from all splits.

  ## Example

      result = DatasetDict.select(dd, [:id, :input])

  """
  @spec select(t(), [atom() | String.t()]) :: t()
  def select(%__MODULE__{} = dd, columns) when is_list(columns) do
    map(dd, fn dataset -> Dataset.select(dataset, columns) end)
  end

  @doc """
  Shuffle all splits.

  ## Options

    * `:seed` - Random seed for reproducible shuffling

  """
  @spec shuffle(t(), keyword()) :: t()
  def shuffle(%__MODULE__{} = dd, opts \\ []) do
    map(dd, fn dataset -> Dataset.shuffle(dataset, opts) end)
  end

  @doc """
  Flatten all splits into a single Dataset.

  ## Example

      combined = DatasetDict.flatten(dd)

  """
  @spec flatten(t()) :: Dataset.t()
  def flatten(%__MODULE__{datasets: datasets}) do
    datasets
    |> Map.values()
    |> Dataset.concat()
  end

  @doc """
  Convert to a plain map.
  """
  @spec to_map(t()) :: %{String.t() => Dataset.t()}
  def to_map(%__MODULE__{datasets: datasets}), do: datasets

  @doc """
  Return the number of rows for each split.
  """
  @spec num_rows(t()) :: %{String.t() => non_neg_integer()}
  def num_rows(%__MODULE__{datasets: datasets}) do
    Map.new(datasets, fn {name, dataset} -> {name, Dataset.num_items(dataset)} end)
  end

  @doc """
  Return column names for each split.
  """
  @spec column_names(t()) :: %{String.t() => [atom() | String.t()]}
  def column_names(%__MODULE__{datasets: datasets}) do
    Map.new(datasets, fn {name, dataset} -> {name, Dataset.column_names(dataset)} end)
  end

  @doc """
  Get summary information about the DatasetDict.
  """
  @spec info(t()) :: map()
  def info(%__MODULE__{} = dd) do
    split_counts =
      Map.new(dd.datasets, fn {name, dataset} -> {name, length(dataset.items)} end)

    %{
      num_splits: num_splits(dd),
      total_items: Enum.sum(Map.values(split_counts)),
      splits: split_counts
    }
  end

  @doc """
  Rename a split.

  ## Example

      result = DatasetDict.rename_split(dd, "train", "training")

  """
  @spec rename_split(t(), String.t() | atom(), String.t() | atom()) :: t()
  def rename_split(%__MODULE__{} = dd, old_name, new_name) do
    old_key = normalize_key(old_name)
    new_key = normalize_key(new_name)

    case Map.pop(dd.datasets, old_key) do
      {nil, _} ->
        dd

      {dataset, remaining} ->
        %__MODULE__{
          splits: dd.splits |> MapSet.delete(old_key) |> MapSet.put(new_key),
          datasets: Map.put(remaining, new_key, dataset)
        }
    end
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key

  # ===========================================================================
  # Access Behaviour
  # ===========================================================================

  @behaviour Access

  @impl Access
  def fetch(%__MODULE__{} = dd, key) do
    case get(dd, key) do
      nil -> :error
      dataset -> {:ok, dataset}
    end
  end

  @impl Access
  def get_and_update(%__MODULE__{} = dd, key, fun) do
    current = get(dd, key)

    case fun.(current) do
      {get_value, new_value} ->
        {get_value, put(dd, key, new_value)}

      :pop ->
        {current, delete(dd, key)}
    end
  end

  @impl Access
  def pop(%__MODULE__{} = dd, key) do
    current = get(dd, key)
    {current, delete(dd, key)}
  end

  # ===========================================================================
  # Enumerable Protocol
  # ===========================================================================

  defimpl Enumerable do
    def count(dd) do
      {:ok, MapSet.size(dd.splits)}
    end

    def member?(dd, {name, _dataset}) do
      {:ok, MapSet.member?(dd.splits, name)}
    end

    def member?(_dd, _other), do: {:ok, false}

    def slice(dd) do
      list = Enum.to_list(dd.datasets)
      {:ok, length(list), &Enum.slice(list, &1, &2)}
    end

    def reduce(dd, acc, fun) do
      Enumerable.Map.reduce(dd.datasets, acc, fun)
    end
  end
end
