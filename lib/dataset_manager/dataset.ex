defmodule HfDatasetsEx.Dataset do
  @moduledoc """
  Unified dataset representation across all benchmark types.

  All datasets follow this schema regardless of source (MMLU, HumanEval, GSM8K, custom).
  """

  @type item :: %{
          required(:id) => String.t(),
          required(:input) => input_type(),
          required(:expected) => expected_type(),
          optional(:metadata) => map()
        }

  @type input_type ::
          String.t()
          | %{question: String.t(), choices: [String.t()]}
          | %{signature: String.t(), tests: [String.t()]}

  @type expected_type ::
          String.t()
          | integer()
          | %{answer: String.t(), reasoning: String.t()}

  alias HfDatasetsEx.Features

  @type t :: %__MODULE__{
          name: String.t(),
          version: String.t(),
          items: [item()],
          metadata: map(),
          features: Features.t() | nil
        }

  @enforce_keys [:name, :version, :items, :metadata]
  defstruct [:name, :version, :items, :metadata, features: nil]

  @doc """
  Create a new dataset with validation.
  """
  def new(name, version, items, metadata \\ %{}, features \\ nil) do
    now = DateTime.utc_now()
    features = features || Features.infer_from_items(items)

    full_metadata =
      Map.merge(
        %{
          source: "unknown",
          license: "unknown",
          domain: "general",
          total_items: length(items),
          loaded_at: now,
          checksum: generate_checksum(items)
        },
        metadata
      )

    %__MODULE__{
      name: name,
      version: version,
      items: items,
      metadata: full_metadata,
      features: features
    }
  end

  @doc """
  Validate dataset schema.
  """
  def validate(%__MODULE__{} = dataset) do
    with :ok <- validate_required_fields(dataset),
         :ok <- validate_items(dataset.items),
         :ok <- validate_metadata(dataset.metadata) do
      {:ok, dataset}
    end
  end

  defp validate_required_fields(dataset) do
    required = [:name, :version, :items, :metadata]
    struct_keys = Map.keys(dataset) |> Enum.filter(&(&1 != :__struct__))
    missing = required -- struct_keys

    if missing == [] do
      :ok
    else
      {:error, {:missing_fields, missing}}
    end
  end

  defp validate_items(items) when is_list(items) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case validate_item(item) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_items(_), do: {:error, :items_must_be_list}

  defp validate_item(item) when is_map(item) do
    required = [:id, :input, :expected]
    missing = required -- Map.keys(item)

    if missing == [] do
      :ok
    else
      {:error, {:invalid_item, Map.get(item, :id, "unknown"), missing}}
    end
  end

  defp validate_item(_), do: {:error, :item_must_be_map}

  defp validate_metadata(metadata) when is_map(metadata), do: :ok
  defp validate_metadata(_), do: {:error, :metadata_must_be_map}

  defp generate_checksum(items) do
    content = :erlang.term_to_binary(items)
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  # ===========================================================================
  # Dataset Operations
  # ===========================================================================

  @doc """
  Transform each item in the dataset.

  ## Example

      Dataset.map(dataset, fn item -> Map.put(item, :processed, true) end)

  """
  @spec map(t(), (item() -> item())) :: t()
  def map(%__MODULE__{} = dataset, fun) when is_function(fun, 1) do
    new_items = Enum.map(dataset.items, fun)
    update_items(dataset, new_items)
  end

  @doc """
  Filter items by predicate function.

  ## Example

      Dataset.filter(dataset, fn item -> item.metadata.difficulty == "easy" end)

  """
  @spec filter(t(), (item() -> boolean())) :: t()
  def filter(%__MODULE__{} = dataset, fun) when is_function(fun, 1) do
    new_items = Enum.filter(dataset.items, fun)
    update_items(dataset, new_items)
  end

  @doc """
  Randomize item order.

  ## Options

    * `:seed` - Random seed for reproducible shuffling

  ## Example

      Dataset.shuffle(dataset)
      Dataset.shuffle(dataset, seed: 42)

  """
  @spec shuffle(t(), keyword()) :: t()
  def shuffle(%__MODULE__{} = dataset, opts \\ []) do
    new_items =
      case Keyword.get(opts, :seed) do
        nil ->
          Enum.shuffle(dataset.items)

        seed ->
          # Use seeded random for deterministic shuffle
          :rand.seed(:exsss, {seed, seed, seed})
          Enum.shuffle(dataset.items)
      end

    update_items(dataset, new_items)
  end

  @doc """
  Select specific columns from each item.

  ## Example

      Dataset.select(dataset, [:id, :input])

  """
  @spec select(t(), [atom() | String.t()] | [non_neg_integer()] | Range.t()) :: t()
  def select(%__MODULE__{} = dataset, %Range{} = range) do
    new_items = Enum.slice(dataset.items, range)
    update_items(dataset, new_items)
  end

  def select(%__MODULE__{} = dataset, indices) when is_list(indices) do
    cond do
      indices == [] ->
        update_items(dataset, [])

      Enum.all?(indices, &is_integer/1) ->
        new_items =
          indices
          |> Enum.map(&Enum.at(dataset.items, &1))
          |> Enum.reject(&is_nil/1)

        update_items(dataset, new_items)

      true ->
        select_columns(dataset, indices)
    end
  end

  defp select_columns(%__MODULE__{} = dataset, columns) do
    new_items =
      Enum.map(dataset.items, fn item ->
        Map.take(item, columns)
      end)

    update_items(dataset, new_items)
  end

  @doc """
  Take first N items from the dataset.

  ## Example

      Dataset.take(dataset, 10)

  """
  @spec take(t(), non_neg_integer()) :: t()
  def take(%__MODULE__{} = dataset, count) when is_integer(count) and count >= 0 do
    new_items = Enum.take(dataset.items, count)
    update_items(dataset, new_items)
  end

  @doc """
  Skip first N items from the dataset.

  ## Example

      Dataset.skip(dataset, 10)

  """
  @spec skip(t(), non_neg_integer()) :: t()
  def skip(%__MODULE__{} = dataset, count) when is_integer(count) and count >= 0 do
    new_items = Enum.drop(dataset.items, count)
    update_items(dataset, new_items)
  end

  @doc """
  Slice the dataset from start index for given length.

  Supports negative start indices to count from end.

  ## Example

      Dataset.slice(dataset, 1, 3)   # items 1, 2, 3 (0-indexed)
      Dataset.slice(dataset, -2, 2)  # last 2 items

  """
  @spec slice(t(), integer(), non_neg_integer()) :: t()
  def slice(%__MODULE__{} = dataset, start, len) do
    new_items = Enum.slice(dataset.items, start, len)
    update_items(dataset, new_items)
  end

  @doc """
  Split dataset into multiple batches.

  Returns a list of Dataset structs.

  ## Example

      batches = Dataset.batch(dataset, 32)

  """
  @spec batch(t(), pos_integer()) :: [t()]
  def batch(%__MODULE__{} = dataset, size) when is_integer(size) and size > 0 do
    dataset.items
    |> Enum.chunk_every(size)
    |> Enum.with_index()
    |> Enum.map(fn {items, idx} ->
      %__MODULE__{
        name: "#{dataset.name}_batch_#{idx}",
        version: dataset.version,
        items: items,
        metadata: Map.put(dataset.metadata, :total_items, length(items)),
        features: dataset.features
      }
    end)
  end

  @doc """
  Concatenate two datasets.

  ## Example

      combined = Dataset.concat(dataset1, dataset2)

  """
  @spec concat(t(), t()) :: t()
  def concat(%__MODULE__{} = dataset1, %__MODULE__{} = dataset2) do
    new_items = dataset1.items ++ dataset2.items
    update_items(dataset1, new_items)
  end

  @doc """
  Concatenate a list of datasets.

  ## Example

      combined = Dataset.concat([d1, d2, d3])

  """
  @spec concat([t()]) :: t()
  def concat([single]), do: single

  def concat([first | rest]) do
    Enum.reduce(rest, first, &concat(&2, &1))
  end

  @doc """
  Split dataset into train/test portions.

  ## Options

    * First argument can be a float ratio (0.0-1.0) for train portion
    * `:train_size` - Exact number of train items
    * `:test_size` - Exact number of test items

  ## Example

      {train, test} = Dataset.split(dataset, 0.8)
      {train, test} = Dataset.split(dataset, train_size: 100, test_size: 20)

  """
  @spec split(t(), float() | keyword()) :: {t(), t()}
  def split(%__MODULE__{} = dataset, ratio) when is_float(ratio) do
    train_size = round(length(dataset.items) * ratio)
    {train_items, test_items} = Enum.split(dataset.items, train_size)

    train = %__MODULE__{
      name: "#{dataset.name}_train",
      version: dataset.version,
      items: train_items,
      metadata: Map.put(dataset.metadata, :total_items, length(train_items))
    }

    test = %__MODULE__{
      name: "#{dataset.name}_test",
      version: dataset.version,
      items: test_items,
      metadata: Map.put(dataset.metadata, :total_items, length(test_items))
    }

    {train, test}
  end

  def split(%__MODULE__{} = dataset, opts) when is_list(opts) do
    train_size = Keyword.get(opts, :train_size)
    {train_items, test_items} = Enum.split(dataset.items, train_size)

    train = %__MODULE__{
      name: "#{dataset.name}_train",
      version: dataset.version,
      items: train_items,
      metadata: Map.put(dataset.metadata, :total_items, length(train_items))
    }

    test = %__MODULE__{
      name: "#{dataset.name}_test",
      version: dataset.version,
      items: test_items,
      metadata: Map.put(dataset.metadata, :total_items, length(test_items))
    }

    {train, test}
  end

  @doc """
  Create shards of the dataset.

  ## Options

    * `:num_shards` - Number of shards to create
    * `:index` - (Optional) Return only the shard at this index

  ## Example

      shards = Dataset.shard(dataset, num_shards: 4)
      shard = Dataset.shard(dataset, num_shards: 4, index: 0)

  """
  @spec shard(t(), keyword()) :: [t()] | t()
  def shard(%__MODULE__{} = dataset, opts) do
    num_shards = Keyword.fetch!(opts, :num_shards)
    index = Keyword.get(opts, :index)

    total = length(dataset.items)
    shard_size = div(total, num_shards)
    remainder = rem(total, num_shards)

    shards =
      0..(num_shards - 1)
      |> Enum.map(fn idx ->
        # Distribute remainder items to first shards
        start = idx * shard_size + min(idx, remainder)
        extra = if idx < remainder, do: 1, else: 0
        size = shard_size + extra

        items = Enum.slice(dataset.items, start, size)

        %__MODULE__{
          name: "#{dataset.name}_shard_#{idx}",
          version: dataset.version,
          items: items,
          metadata: Map.put(dataset.metadata, :total_items, length(items))
        }
      end)

    if index, do: Enum.at(shards, index), else: shards
  end

  @doc """
  Rename a column in all items.

  ## Example

      Dataset.rename_column(dataset, :input, :prompt)

  """
  @spec rename_column(t(), atom() | String.t(), atom() | String.t()) :: t()
  def rename_column(%__MODULE__{} = dataset, old_name, new_name) do
    new_items =
      Enum.map(dataset.items, fn item ->
        case Map.pop(item, old_name) do
          {nil, item} -> item
          {value, item} -> Map.put(item, new_name, value)
        end
      end)

    update_items(dataset, new_items)
  end

  @doc """
  Add a new column computed from each item.

  The function receives the item and its index.

  ## Example

      Dataset.add_column(dataset, :index, fn _item, idx -> idx end)
      Dataset.add_column(dataset, :length, fn item, _idx -> String.length(item.input) end)

  """
  @spec add_column(t(), atom() | String.t(), (item(), integer() -> term())) :: t()
  def add_column(%__MODULE__{} = dataset, name, fun) when is_function(fun, 2) do
    new_items =
      dataset.items
      |> Enum.with_index()
      |> Enum.map(fn {item, idx} ->
        Map.put(item, name, fun.(item, idx))
      end)

    update_items(dataset, new_items)
  end

  @doc """
  Remove columns from all items.

  ## Example

      Dataset.remove_columns(dataset, [:metadata, :extra_field])

  """
  @spec remove_columns(t(), [atom() | String.t()]) :: t()
  def remove_columns(%__MODULE__{} = dataset, columns) when is_list(columns) do
    new_items =
      Enum.map(dataset.items, fn item ->
        Map.drop(item, columns)
      end)

    update_items(dataset, new_items)
  end

  @doc """
  Keep only unique items by a column.

  ## Example

      Dataset.unique(dataset, :category)

  """
  @spec unique(t(), atom() | String.t()) :: t()
  def unique(%__MODULE__{} = dataset, column) do
    new_items = Enum.uniq_by(dataset.items, &Map.get(&1, column))
    update_items(dataset, new_items)
  end

  @doc """
  Sort items by a column.

  ## Example

      Dataset.sort(dataset, :id, :asc)
      Dataset.sort(dataset, :score, :desc)

  """
  @spec sort(t(), atom() | String.t(), :asc | :desc) :: t()
  def sort(%__MODULE__{} = dataset, column, direction \\ :asc) do
    sorter =
      case direction do
        :asc -> &<=/2
        :desc -> &>=/2
      end

    new_items = Enum.sort_by(dataset.items, &Map.get(&1, column), sorter)
    update_items(dataset, new_items)
  end

  @doc """
  Flatten a nested column into top-level keys.

  Keys are prefixed with the original column name.

  ## Example

      # %{nested: %{a: 1, b: 2}} becomes %{nested_a: 1, nested_b: 2}
      Dataset.flatten(dataset, :nested)

  """
  @spec flatten(t(), atom() | String.t()) :: t()
  def flatten(%__MODULE__{} = dataset, column) do
    new_items =
      Enum.map(dataset.items, fn item ->
        case Map.get(item, column) do
          nested when is_map(nested) ->
            flattened =
              Enum.reduce(nested, item, fn {k, v}, acc ->
                new_key =
                  cond do
                    is_atom(column) and is_atom(k) ->
                      String.to_atom("#{column}_#{k}")

                    is_atom(column) ->
                      String.to_atom("#{column}_#{k}")

                    true ->
                      "#{column}_#{k}"
                  end

                Map.put(acc, new_key, v)
              end)

            Map.delete(flattened, column)

          _ ->
            item
        end
      end)

    update_items(dataset, new_items)
  end

  @doc """
  Get items as a list.

  ## Example

      items = Dataset.to_list(dataset)

  """
  @spec to_list(t()) :: [item()]
  def to_list(%__MODULE__{items: items}), do: items

  @doc """
  Get the number of items.

  ## Example

      count = Dataset.num_items(dataset)

  """
  @spec num_items(t()) :: non_neg_integer()
  def num_items(%__MODULE__{items: items}), do: Kernel.length(items)

  @doc """
  Get column names from the first item.

  ## Example

      names = Dataset.column_names(dataset)

  """
  @spec column_names(t()) :: [atom() | String.t()]
  def column_names(%__MODULE__{items: []}), do: []
  def column_names(%__MODULE__{items: [first | _]}), do: Map.keys(first)

  @doc """
  Create a dataset from a list of maps.

  ## Options
    * `:name` - Dataset name (default: \"dataset\")\n    * `:version` - Dataset version (default: \"1.0\")\n    * `:metadata` - Dataset metadata map (default: %{})\n
  """
  @spec from_list([map()], keyword()) :: t()
  def from_list(items, opts \\ []) when is_list(items) do
    name = Keyword.get(opts, :name, "dataset")
    version = Keyword.get(opts, :version, "1.0")
    metadata = Keyword.get(opts, :metadata, %{})

    new(name, version, items, metadata)
  end

  @doc """
  Create a dataset from an Explorer DataFrame.
  """
  @spec from_dataframe(Explorer.DataFrame.t(), keyword()) :: t()
  def from_dataframe(%Explorer.DataFrame{} = df, opts \\ []) do
    items =
      df
      |> Explorer.DataFrame.to_rows()
      |> Enum.map(&stringify_keys/1)

    from_list(items, opts)
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  # Helper to update items and recalculate metadata
  defp update_items(dataset, new_items) do
    new_metadata = Map.put(dataset.metadata, :total_items, Kernel.length(new_items))

    %__MODULE__{
      dataset
      | items: new_items,
        metadata: new_metadata
    }
  end

  # ===========================================================================
  # Enumerable Protocol
  # ===========================================================================

  defimpl Enumerable do
    def count(dataset) do
      {:ok, Kernel.length(dataset.items)}
    end

    def member?(dataset, element) do
      {:ok, element in dataset.items}
    end

    def slice(dataset) do
      size = Kernel.length(dataset.items)
      {:ok, size, &Enum.slice(dataset.items, &1, &2)}
    end

    def reduce(dataset, acc, fun) do
      Enumerable.List.reduce(dataset.items, acc, fun)
    end
  end

  # ===========================================================================
  # Access Behaviour
  # ===========================================================================

  @behaviour Access

  @impl Access
  def fetch(%__MODULE__{items: items}, index) when is_integer(index) do
    case Enum.at(items, index) do
      nil -> :error
      item -> {:ok, item}
    end
  end

  def fetch(%__MODULE__{}, _key), do: :error

  @impl Access
  def get_and_update(%__MODULE__{items: items} = dataset, index, fun) when is_integer(index) do
    {old_value, new_items} = List.pop_at(items, normalize_index(index, items))

    case fun.(old_value) do
      {get_value, new_value} ->
        updated_items = List.replace_at(items, normalize_index(index, items), new_value)
        {get_value, %{dataset | items: updated_items}}

      :pop ->
        {old_value, %{dataset | items: new_items}}
    end
  end

  @impl Access
  def pop(%__MODULE__{items: items} = dataset, index) when is_integer(index) do
    {value, new_items} = List.pop_at(items, normalize_index(index, items))
    {value, %{dataset | items: new_items}}
  end

  defp normalize_index(index, items) when index < 0 do
    Kernel.length(items) + index
  end

  defp normalize_index(index, _items), do: index
end
