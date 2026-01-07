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

  alias HfDatasetsEx.{Config, Fingerprint, TransformCache}
  alias HfDatasetsEx.Export.Arrow
  alias HfDatasetsEx.Export.Text
  alias HfDatasetsEx.Features
  alias HfDatasetsEx.Features.ClassLabel
  alias HfDatasetsEx.Format.CSV
  alias HfDatasetsEx.Format.JSON
  alias HfDatasetsEx.Format.JSONL
  alias HfDatasetsEx.Format.Parquet
  alias HfDatasetsEx.Formatter
  alias HfDatasetsEx.Index.BruteForce
  alias HfDatasetsEx.IterableDataset
  alias HfDatasetsEx.PRNG.PCG64

  @type t :: %__MODULE__{
          name: String.t(),
          version: String.t(),
          items: [item()],
          metadata: map(),
          features: Features.t() | nil,
          fingerprint: Fingerprint.t() | nil,
          format: Formatter.format_type(),
          format_columns: [String.t() | atom()] | nil,
          format_opts: keyword()
        }

  @enforce_keys [:name, :version, :items, :metadata]
  defstruct [
    :name,
    :version,
    :items,
    :metadata,
    :features,
    :fingerprint,
    format: :elixir,
    format_columns: nil,
    format_opts: []
  ]

  @doc """
  Get or compute the fingerprint for this dataset.
  """
  @spec fingerprint(t()) :: Fingerprint.t()
  def fingerprint(%__MODULE__{fingerprint: fp}) when not is_nil(fp), do: fp
  def fingerprint(%__MODULE__{} = dataset), do: Fingerprint.from_dataset(dataset)

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

  @doc """
  Set the output format for the dataset.

  ## Options

    * `:columns` - List of columns to include in formatted output
    * `:dtype` - Force specific data type (e.g., `:float32`)

  ## Examples

      dataset
      |> Dataset.set_format(:nx, columns: ["input_ids", "labels"])
      |> Enum.each(fn batch -> ... end)

  """
  @spec set_format(t(), Formatter.format_type(), keyword()) :: t()
  def set_format(%__MODULE__{} = dataset, format, opts \\ []) do
    %{
      dataset
      | format: format,
        format_columns: Keyword.get(opts, :columns),
        format_opts: opts
    }
  end

  @doc """
  Return a copy with the specified format (doesn't modify original).
  """
  @spec with_format(t(), Formatter.format_type(), keyword()) :: t()
  def with_format(%__MODULE__{} = dataset, format, opts \\ []) do
    set_format(dataset, format, opts)
  end

  @doc """
  Reset format to default (Elixir maps).
  """
  @spec reset_format(t()) :: t()
  def reset_format(%__MODULE__{} = dataset) do
    %{dataset | format: :elixir, format_columns: nil, format_opts: []}
  end

  @doc """
  Iterate over dataset in batches with formatting applied.

  ## Options

    * `:batch_size` - Number of items per batch (default: 32)
    * `:drop_last` - Drop last batch if incomplete (default: false)

  ## Examples

      dataset
      |> Dataset.set_format(:nx)
      |> Dataset.iter(batch_size: 32)
      |> Enum.each(fn batch ->
        # batch is %{"col1" => Nx.Tensor, "col2" => Nx.Tensor}
      end)

  """
  @spec iter(t(), keyword()) :: Enumerable.t()
  def iter(%__MODULE__{} = dataset, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 32)
    drop_last = Keyword.get(opts, :drop_last, false)

    formatter = Formatter.get(dataset.format)
    format_opts = dataset.format_opts

    chunker = if drop_last, do: :discard, else: []

    dataset.items
    |> Stream.chunk_every(batch_size, batch_size, chunker)
    |> Stream.map(&formatter.format_batch(&1, format_opts))
  end

  @doc """
  Add a search index for a column.

  ## Options

    * `:metric` - Distance metric: :cosine, :l2, :inner_product (default: :cosine)
    * `:index_type` - Index implementation (default: :brute_force)

  ## Examples

      dataset = Dataset.add_index(dataset, "embeddings", metric: :cosine)

  """
  @spec add_index(t(), String.t(), keyword()) :: t()
  def add_index(%__MODULE__{} = dataset, column, opts \\ []) do
    metric = Keyword.get(opts, :metric, :cosine)
    index_type = Keyword.get(opts, :index_type, :brute_force)

    vectors = column_vectors(dataset.items, column)

    index =
      case index_type do
        :brute_force ->
          BruteForce.new(column, metric: metric)
          |> BruteForce.add(vectors)
      end

    indices = Map.get(dataset.metadata, :indices, %{})
    metadata = Map.put(dataset.metadata, :indices, Map.put(indices, column, index))

    %{dataset | metadata: metadata}
  end

  @doc """
  Search for nearest examples to a query vector.

  ## Examples

      {scores, examples} = Dataset.get_nearest_examples(dataset, "embeddings", query, k: 10)

  """
  @spec get_nearest_examples(t(), String.t(), Nx.Tensor.t(), keyword()) ::
          {[float()], [map()]}
  def get_nearest_examples(%__MODULE__{} = dataset, column, query, opts \\ []) do
    k = Keyword.get(opts, :k, 10)

    index = get_in(dataset.metadata, [:indices, column])

    unless index do
      raise ArgumentError, """
      No index found for column "#{column}".
      Call Dataset.add_index(dataset, "#{column}") first.
      """
    end

    results = BruteForce.search(index, query, k)

    scores = Enum.map(results, fn {score, _idx} -> score end)
    examples = Enum.map(results, fn {_score, idx} -> Enum.at(dataset.items, idx) end)

    {scores, examples}
  end

  @doc """
  Save an index to a file.
  """
  @spec save_index(t(), String.t(), Path.t()) :: :ok | {:error, term()}
  def save_index(%__MODULE__{} = dataset, column, path) do
    index = get_in(dataset.metadata, [:indices, column])

    if index do
      BruteForce.save(index, path)
    else
      {:error, {:no_index, column}}
    end
  end

  @doc """
  Load an index from a file.
  """
  @spec load_index(t(), String.t(), Path.t()) :: {:ok, t()} | {:error, term()}
  def load_index(%__MODULE__{} = dataset, column, path) do
    case BruteForce.load(path) do
      {:ok, index} ->
        index = %{index | column: column}
        indices = Map.get(dataset.metadata, :indices, %{})
        metadata = Map.put(dataset.metadata, :indices, Map.put(indices, column, index))
        {:ok, %{dataset | metadata: metadata}}

      error ->
        error
    end
  end

  @doc """
  Remove an index.
  """
  @spec drop_index(t(), String.t()) :: t()
  def drop_index(%__MODULE__{} = dataset, column) do
    indices = Map.get(dataset.metadata, :indices, %{})
    metadata = Map.put(dataset.metadata, :indices, Map.delete(indices, column))
    %{dataset | metadata: metadata}
  end

  defp column_vectors(items, column) do
    tensors =
      items
      |> Enum.map(&Map.get(&1, column))
      |> Enum.map(fn
        %Nx.Tensor{} = tensor -> tensor
        value -> Nx.tensor(value)
      end)

    case tensors do
      [] -> Nx.tensor([])
      _ -> Nx.stack(tensors)
    end
  end

  # ===========================================================================
  # Dataset Operations
  # ===========================================================================

  @doc """
  Map with optional caching.

  ## Options

    * `:cache` - Enable caching (default: true if caching enabled globally)
    * `:new_fingerprint` - Custom fingerprint for result
    * `:batched` - Apply in batches (default: false)
    * `:batch_size` - Batch size for batched map (default: 1000)

  ## Example

      Dataset.map(dataset, fn item -> Map.put(item, :processed, true) end)

  """
  @spec map(t(), (map() -> map()), keyword()) :: t()
  def map(%__MODULE__{} = dataset, fun, opts \\ []) when is_function(fun, 1) do
    use_cache = Keyword.get(opts, :cache, caching_enabled?())

    if use_cache do
      map_cached(dataset, fun, opts)
    else
      dataset
      |> map_uncached(fun, opts)
      |> maybe_apply_custom_fingerprint(opts)
    end
  end

  defp map_cached(dataset, fun, opts) do
    input_fp = fingerprint(dataset)
    transform_fp = Fingerprint.generate(:map, [fun], opts)

    case TransformCache.get(input_fp, transform_fp) do
      {:ok, cached} ->
        apply_transform_fingerprint(cached, input_fp, transform_fp, opts)

      :miss ->
        result = map_uncached(dataset, fun, opts)
        result = apply_transform_fingerprint(result, input_fp, transform_fp, opts)

        TransformCache.put(input_fp, transform_fp, result)
        result
    end
  end

  defp map_uncached(dataset, fun, opts) do
    batched = Keyword.get(opts, :batched, false)
    batch_size = Keyword.get(opts, :batch_size, 1000)

    new_items =
      if batched do
        dataset.items
        |> Enum.chunk_every(batch_size)
        |> Enum.flat_map(fun)
      else
        Enum.map(dataset.items, fun)
      end

    update_items(dataset, new_items)
  end

  @doc """
  Filter with optional caching.
  """
  @spec filter(t(), (map() -> boolean()), keyword()) :: t()
  def filter(%__MODULE__{} = dataset, predicate, opts \\ []) when is_function(predicate, 1) do
    use_cache = Keyword.get(opts, :cache, caching_enabled?())

    if use_cache do
      filter_cached(dataset, predicate, opts)
    else
      dataset
      |> filter_uncached(predicate, opts)
      |> maybe_apply_custom_fingerprint(opts)
    end
  end

  defp filter_cached(dataset, predicate, opts) do
    input_fp = fingerprint(dataset)
    transform_fp = Fingerprint.generate(:filter, [predicate], opts)

    case TransformCache.get(input_fp, transform_fp) do
      {:ok, cached} ->
        apply_transform_fingerprint(cached, input_fp, transform_fp, opts)

      :miss ->
        result = filter_uncached(dataset, predicate, opts)
        result = apply_transform_fingerprint(result, input_fp, transform_fp, opts)

        TransformCache.put(input_fp, transform_fp, result)
        result
    end
  end

  defp filter_uncached(dataset, predicate, _opts) do
    new_items = Enum.filter(dataset.items, predicate)
    update_items(dataset, new_items)
  end

  @doc """
  Randomize item order.

  ## Options

    * `:seed` - Random seed for reproducible shuffling
    * `:generator` - PRNG to use: `:numpy` (PCG64, matches Python, default) or `:erlang`

  ## Example

      Dataset.shuffle(dataset)
      Dataset.shuffle(dataset, seed: 42)  # Matches Python's datasets.shuffle(seed=42)
      Dataset.shuffle(dataset, seed: 42, generator: :erlang)  # Use Erlang's PRNG

  """
  @spec shuffle(t(), keyword()) :: t()
  def shuffle(%__MODULE__{} = dataset, opts \\ []) do
    seed = Keyword.get(opts, :seed)
    generator = Keyword.get(opts, :generator, :numpy)

    new_items =
      case {seed, generator} do
        {nil, _} ->
          Enum.shuffle(dataset.items)

        {seed, :numpy} ->
          # Use PCG64 for exact NumPy compatibility
          pcg_state = PCG64.seed(seed)
          {shuffled, _state} = PCG64.shuffle(dataset.items, pcg_state)
          shuffled

        {seed, :erlang} ->
          # Use Erlang's PRNG (faster but different order than Python)
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
        features: dataset.features,
        format: dataset.format,
        format_columns: dataset.format_columns,
        format_opts: dataset.format_opts
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
  Cast the dataset to a new feature schema.

  ## Examples

      new_features =
        Features.new(%{
          "label" => ClassLabel.new(names: ["neg", "pos"]),
          "score" => %Features.Value{dtype: :float32}
        })

      {:ok, casted} = Dataset.cast(dataset, new_features)

  """
  @spec cast(t(), Features.t()) :: {:ok, t()} | {:error, term()}
  def cast(%__MODULE__{} = dataset, %Features{} = new_features) do
    with {:ok, casted_items} <- cast_items(dataset.items, new_features) do
      updated = update_items(dataset, casted_items)
      {:ok, %{updated | features: new_features}}
    end
  end

  @doc """
  Cast a single column to a new feature type.

  ## Examples

      Dataset.cast_column(dataset, "label", ClassLabel.new(names: ["neg", "pos"]))

  """
  @spec cast_column(t(), String.t() | atom(), Features.feature_type()) ::
          {:ok, t()} | {:error, term()}
  def cast_column(%__MODULE__{} = dataset, column_name, new_feature) do
    with {:ok, new_items} <- cast_column_items(dataset.items, column_name, new_feature) do
      new_features =
        if dataset.features do
          Features.put(dataset.features, column_name, new_feature)
        else
          nil
        end

      updated = update_items(dataset, new_items)
      {:ok, %{updated | features: new_features}}
    end
  end

  @doc """
  Convert a string column to ClassLabel encoding.

  Automatically infers class names from unique values.

  ## Options

    * `:include_nulls` - Include nil as a class (default: false)

  ## Examples

      {:ok, encoded} = Dataset.class_encode_column(dataset, "sentiment")

  """
  @spec class_encode_column(t(), String.t() | atom(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def class_encode_column(%__MODULE__{} = dataset, column_name, opts \\ []) do
    include_nulls = Keyword.get(opts, :include_nulls, false)

    unique_values = extract_unique_column_values(dataset.items, column_name, include_nulls)
    class_label = ClassLabel.new(names: unique_values)
    encoding = unique_values |> Enum.with_index() |> Map.new()

    new_items = encode_column_items(dataset.items, column_name, encoding, include_nulls)
    new_features = build_class_label_features(dataset.features, column_name, class_label)

    updated = update_items(dataset, new_items)
    {:ok, %{updated | features: new_features}}
  end

  defp extract_unique_column_values(items, column_name, include_nulls) do
    items
    |> Enum.map(&get_column_value(&1, column_name))
    |> Enum.uniq()
    |> Enum.reject(fn value -> is_nil(value) and not include_nulls end)
    |> Enum.sort()
  end

  defp encode_column_items(items, column_name, encoding, include_nulls) do
    Enum.map(items, fn item ->
      encode_single_column_item(item, column_name, encoding, include_nulls)
    end)
  end

  defp encode_single_column_item(item, column_name, encoding, include_nulls) do
    case resolve_item_key(item, column_name) do
      :error -> item
      {:ok, key} -> encode_column_value(item, key, encoding, include_nulls)
    end
  end

  defp encode_column_value(item, key, encoding, include_nulls) do
    value = Map.get(item, key)

    if is_nil(value) and not include_nulls do
      item
    else
      case Map.fetch(encoding, value) do
        {:ok, idx} -> Map.put(item, key, idx)
        :error -> item
      end
    end
  end

  defp build_class_label_features(nil, column_name, class_label) do
    Features.new(%{to_string(column_name) => class_label})
  end

  defp build_class_label_features(features, column_name, class_label) do
    Features.put(features, column_name, class_label)
  end

  @doc """
  Split dataset into train and test sets with optional stratification.

  ## Options

    * `:test_size` - Fraction or count for test set (default: 0.25)
    * `:train_size` - Fraction or count for train set (optional)
    * `:stratify_by_column` - Column to stratify by (optional)
    * `:seed` - Random seed (optional)
    * `:shuffle` - Shuffle before split (default: true)

  """
  @spec train_test_split(t(), keyword()) ::
          {:ok, %{train: t(), test: t()}} | {:error, term()}
  def train_test_split(%__MODULE__{} = dataset, opts \\ []) do
    test_size = Keyword.get(opts, :test_size, 0.25)
    test_size_given? = Keyword.has_key?(opts, :test_size)
    train_size = Keyword.get(opts, :train_size)
    seed = Keyword.get(opts, :seed)
    stratify_col = Keyword.get(opts, :stratify_by_column)
    shuffle? = Keyword.get(opts, :shuffle, true)

    items =
      if shuffle? do
        shuffle(dataset, seed: seed).items
      else
        dataset.items
      end

    with {:ok, {train_count, test_count}} <-
           resolve_split_counts(length(items), train_size, test_size, test_size_given?),
         {:ok, %{train: train_items, test: test_items}} <-
           split_items(items, train_count, test_count, stratify_col) do
      {:ok,
       %{
         train: build_split_dataset(dataset, train_items, "train"),
         test: build_split_dataset(dataset, test_items, "test")
       }}
    end
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
      metadata: Map.put(dataset.metadata, :total_items, length(train_items)),
      format: dataset.format,
      format_columns: dataset.format_columns,
      format_opts: dataset.format_opts
    }

    test = %__MODULE__{
      name: "#{dataset.name}_test",
      version: dataset.version,
      items: test_items,
      metadata: Map.put(dataset.metadata, :total_items, length(test_items)),
      format: dataset.format,
      format_columns: dataset.format_columns,
      format_opts: dataset.format_opts
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
      metadata: Map.put(dataset.metadata, :total_items, length(train_items)),
      format: dataset.format,
      format_columns: dataset.format_columns,
      format_opts: dataset.format_opts
    }

    test = %__MODULE__{
      name: "#{dataset.name}_test",
      version: dataset.version,
      items: test_items,
      metadata: Map.put(dataset.metadata, :total_items, length(test_items)),
      format: dataset.format,
      format_columns: dataset.format_columns,
      format_opts: dataset.format_opts
    }

    {train, test}
  end

  defp cast_items(items, %Features{} = features) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case cast_item(item, features) do
        {:ok, casted} -> {:cont, {:ok, [casted | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, casted} -> {:ok, Enum.reverse(casted)}
      {:error, _} = error -> error
    end
  end

  defp cast_item(item, %Features{schema: schema}) do
    Enum.reduce_while(item, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      cast_item_field(acc, key, value, feature_for_key(schema, key))
    end)
  end

  defp cast_item_field(acc, key, value, nil) do
    {:cont, {:ok, Map.put(acc, key, value)}}
  end

  defp cast_item_field(acc, key, value, feature) do
    case Features.cast_value(value, feature) do
      {:ok, casted} -> {:cont, {:ok, Map.put(acc, key, casted)}}
      {:error, reason} -> {:halt, {:error, {:cast_error, key, reason}}}
    end
  end

  defp cast_column_items(items, column_name, feature) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case cast_single_column_item(item, column_name, feature) do
        {:ok, casted_item} -> {:cont, {:ok, [casted_item | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, casted} -> {:ok, Enum.reverse(casted)}
      {:error, _} = error -> error
    end
  end

  defp cast_single_column_item(item, column_name, feature) do
    case resolve_item_key(item, column_name) do
      :error -> {:ok, item}
      {:ok, key} -> cast_item_column_value(item, key, feature)
    end
  end

  defp cast_item_column_value(item, key, feature) do
    case Features.cast_value(Map.get(item, key), feature) do
      {:ok, casted} -> {:ok, Map.put(item, key, casted)}
      {:error, reason} -> {:error, {:cast_error, key, reason}}
    end
  end

  defp feature_for_key(schema, key) do
    Map.get(schema, key) || Map.get(schema, to_string(key))
  end

  defp resolve_item_key(item, column_name) do
    if Map.has_key?(item, column_name) do
      {:ok, column_name}
    else
      find_key_by_string(item, to_string(column_name))
    end
  end

  defp find_key_by_string(item, column_str) do
    case Enum.find(Map.keys(item), fn key -> to_string(key) == column_str end) do
      nil -> :error
      key -> {:ok, key}
    end
  end

  defp get_column_value(item, column_name) do
    case resolve_item_key(item, column_name) do
      {:ok, key} -> Map.get(item, key)
      :error -> nil
    end
  end

  defp resolve_split_counts(total, train_size, test_size, test_size_given?) do
    with {:ok, test_count} <- size_to_count(total, test_size, :test_size),
         {:ok, train_count} <- size_to_count(total, train_size, :train_size, allow_nil: true) do
      cond do
        total == 0 ->
          {:ok, {0, 0}}

        is_nil(train_count) ->
          {:ok, {total - test_count, test_count}}

        not test_size_given? ->
          {:ok, {train_count, total - train_count}}

        train_count + test_count > total ->
          {:error, :invalid_split_sizes}

        train_count + test_count < total ->
          {:ok, {train_count, total - train_count}}

        true ->
          {:ok, {train_count, test_count}}
      end
    end
  end

  defp size_to_count(total, size, label, opts \\ [])

  defp size_to_count(_total, nil, label, opts) do
    if Keyword.get(opts, :allow_nil, false) do
      {:ok, nil}
    else
      {:error, {label, :invalid_type}}
    end
  end

  defp size_to_count(total, size, label, _opts) when is_float(size) do
    if size < 0.0 or size > 1.0 do
      {:error, {label, :out_of_range}}
    else
      {:ok, round(total * size)}
    end
  end

  defp size_to_count(total, size, label, _opts) when is_integer(size) do
    if size < 0 or size > total do
      {:error, {label, :out_of_range}}
    else
      {:ok, size}
    end
  end

  defp size_to_count(_total, _size, label, _opts) do
    {:error, {label, :invalid_type}}
  end

  defp split_items([], _train_count, _test_count, _column) do
    {:ok, %{train: [], test: []}}
  end

  defp split_items(items, train_count, _test_count, nil) do
    {train_items, test_items} = Enum.split(items, train_count)
    {:ok, %{train: train_items, test: test_items}}
  end

  defp split_items(items, _train_count, test_count, column) do
    grouped = Enum.group_by(items, &Map.get(&1, column))
    allocations = stratified_allocations(grouped, test_count, length(items))

    {train_items, test_items} =
      Enum.reduce(grouped, {[], []}, fn {label, group_items}, {train_acc, test_acc} ->
        test_n = Map.get(allocations, label, 0)
        {group_train, group_test} = Enum.split(group_items, length(group_items) - test_n)
        {train_acc ++ group_train, test_acc ++ group_test}
      end)

    {:ok, %{train: train_items, test: test_items}}
  end

  defp stratified_allocations(_grouped, _test_count, 0), do: %{}

  defp stratified_allocations(grouped, test_count, total) do
    base =
      grouped
      |> Enum.map(fn {label, items} ->
        exact = length(items) / total * test_count
        floored = floor(exact)
        {label, floored, exact - floored}
      end)

    base_sum = Enum.reduce(base, 0, fn {_label, count, _}, acc -> acc + count end)
    remainder = max(test_count - base_sum, 0)

    extra =
      base
      |> Enum.sort_by(fn {_label, _count, frac} -> -frac end)
      |> Enum.take(remainder)
      |> Enum.map(fn {label, _count, _frac} -> label end)

    base
    |> Enum.map(fn {label, count, _frac} ->
      extra_count = if label in extra, do: 1, else: 0
      {label, count + extra_count}
    end)
    |> Map.new()
  end

  defp build_split_dataset(%__MODULE__{} = dataset, items, suffix) do
    updated = update_items(dataset, items)
    %{updated | name: "#{dataset.name}_#{suffix}"}
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
          metadata: Map.put(dataset.metadata, :total_items, length(items)),
          format: dataset.format,
          format_columns: dataset.format_columns,
          format_opts: dataset.format_opts
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
    new_items = Enum.map(dataset.items, &flatten_item(&1, column))

    update_items(dataset, new_items)
  end

  defp flatten_item(item, column) do
    case Map.get(item, column) do
      nested when is_map(nested) ->
        flattened = Enum.reduce(nested, item, &flatten_nested_key(&1, &2, column))
        Map.delete(flattened, column)

      _ ->
        item
    end
  end

  defp flatten_nested_key({k, v}, acc, column) do
    new_key = build_flattened_key(column, k)
    Map.put(acc, new_key, v)
  end

  defp build_flattened_key(column, k) when is_atom(column), do: String.to_atom("#{column}_#{k}")
  defp build_flattened_key(column, k), do: "#{column}_#{k}"

  @doc """
  Convert dataset to a column-oriented dictionary.

  ## Options

    * `:columns` - Specific columns to include (default: all)

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
  Export dataset to CSV file.

  See `HfDatasetsEx.Export.to_csv/3` for options.
  """
  @spec to_csv(t(), Path.t(), keyword()) :: :ok | {:error, term()}
  defdelegate to_csv(dataset, path, opts \\ []), to: HfDatasetsEx.Export

  @doc """
  Export dataset to JSON file.

  See `HfDatasetsEx.Export.to_json/3` for options.
  """
  @spec to_json(t(), Path.t(), keyword()) :: :ok | {:error, term()}
  defdelegate to_json(dataset, path, opts \\ []), to: HfDatasetsEx.Export

  @doc """
  Export dataset to JSONL file.
  """
  @spec to_jsonl(t(), Path.t(), keyword()) :: :ok | {:error, term()}
  defdelegate to_jsonl(dataset, path, opts \\ []), to: HfDatasetsEx.Export

  @doc """
  Export dataset to Parquet file.

  See `HfDatasetsEx.Export.to_parquet/3` for options.
  """
  @spec to_parquet(t(), Path.t(), keyword()) :: :ok | {:error, term()}
  defdelegate to_parquet(dataset, path, opts \\ []), to: HfDatasetsEx.Export

  @doc """
  Export dataset to plain text file.

  See `HfDatasetsEx.Export.Text.write/3` for options.
  """
  @spec to_text(t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def to_text(%__MODULE__{} = dataset, path, opts \\ []) do
    Text.write(dataset, path, opts)
  end

  @doc """
  Export dataset to Arrow IPC file.

  See `HfDatasetsEx.Export.Arrow.write/3` for options.
  """
  @spec to_arrow(t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def to_arrow(%__MODULE__{} = dataset, path, opts \\ []) do
    Arrow.write(dataset, path, opts)
  end

  @doc """
  Push a dataset to HuggingFace Hub.
  """
  @spec push_to_hub(t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  defdelegate push_to_hub(dataset, repo_id, opts \\ []), to: HfDatasetsEx.Hub

  @doc """
  Create a dataset from a generator function.

  The generator should return an Enumerable that yields maps.

  ## Options

    * `:eager` - Immediately materialize (default: false, returns IterableDataset)
    * `:features` - Feature schema
    * `:name` - Dataset name

  ## Examples

      # Returns IterableDataset (lazy)
      Dataset.from_generator(fn ->
        Stream.repeatedly(fn -> %{"x" => :rand.uniform()} end)
        |> Stream.take(100)
      end)

      # Returns Dataset (eager)
      Dataset.from_generator(
        fn -> 1..100 |> Stream.map(&%{"x" => &1}) end,
        eager: true
      )

  """
  @spec from_generator((-> Enumerable.t()), keyword()) :: IterableDataset.t() | t()
  def from_generator(generator_fn, opts \\ []) when is_function(generator_fn, 0) do
    eager = Keyword.get(opts, :eager, false)
    name = Keyword.get(opts, :name, "generated")
    features = Keyword.get(opts, :features)
    metadata = Keyword.get(opts, :metadata, %{})

    stream = Stream.flat_map([nil], fn _ -> generator_fn.() end)

    if eager do
      items = Enum.to_list(stream)

      opts =
        opts
        |> Keyword.put(:name, name)
        |> Keyword.put(:features, features)

      from_list(items, opts)
    else
      info =
        if is_nil(features) do
          metadata
        else
          Map.put(metadata, :features, features)
        end

      IterableDataset.from_stream(stream, name: name, info: info)
    end
  end

  @doc """
  Create a dataset from a CSV file.

  ## Options

    * `:delimiter` - Field delimiter (default: ",")
    * `:headers` - Use first row as headers (default: true)
    * `:features` - Feature schema
    * `:name` - Dataset name (default: filename)

  ## Examples

      Dataset.from_csv("/path/to/data.csv")
      Dataset.from_csv("/path/to/data.tsv", delimiter: "\\t")

  """
  @spec from_csv(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_csv(path, opts \\ []) when is_binary(path) do
    name = Keyword.get(opts, :name, Path.basename(path) |> Path.rootname())

    with {:ok, items} <- CSV.parse(path, opts) do
      opts = Keyword.put(opts, :name, name)
      {:ok, from_list(items, opts)}
    end
  end

  @doc """
  Same as `from_csv/2` but raises on error.
  """
  @spec from_csv!(Path.t(), keyword()) :: t()
  def from_csv!(path, opts \\ []) do
    case from_csv(path, opts) do
      {:ok, dataset} -> dataset
      {:error, error} -> raise RuntimeError, "Failed to load CSV: #{inspect(error)}"
    end
  end

  @doc """
  Create a dataset from a JSON file.

  Supports both single JSON array and JSONL (one JSON object per line).

  ## Options

    * `:features` - Feature schema
    * `:name` - Dataset name

  ## Examples

      # JSON array
      Dataset.from_json("/path/to/data.json")

      # JSONL (auto-detected by .jsonl extension)
      Dataset.from_json("/path/to/data.jsonl")

  """
  @spec from_json(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_json(path, opts \\ []) when is_binary(path) do
    name = Keyword.get(opts, :name, Path.basename(path) |> Path.rootname())
    ext = path |> Path.extname() |> String.downcase()

    parser =
      if ext in [".jsonl", ".jsonlines", ".ndjson"] do
        JSONL
      else
        JSON
      end

    with {:ok, items} <- parser.parse(path) do
      opts = Keyword.put(opts, :name, name)
      {:ok, from_list(items, opts)}
    end
  end

  @doc """
  Same as `from_json/2` but raises on error.
  """
  @spec from_json!(Path.t(), keyword()) :: t()
  def from_json!(path, opts \\ []) do
    case from_json(path, opts) do
      {:ok, dataset} -> dataset
      {:error, error} -> raise RuntimeError, "Failed to load JSON: #{inspect(error)}"
    end
  end

  @doc """
  Create a dataset from a Parquet file.

  ## Options

    * `:columns` - Select specific columns
    * `:features` - Feature schema
    * `:name` - Dataset name

  ## Examples

      Dataset.from_parquet("/path/to/data.parquet")
      Dataset.from_parquet("/path/to/data.parquet", columns: ["id", "text"])

  """
  @spec from_parquet(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_parquet(path, opts \\ []) when is_binary(path) do
    name = Keyword.get(opts, :name, Path.basename(path) |> Path.rootname())
    columns = Keyword.get(opts, :columns)
    columns = if columns, do: Enum.map(columns, &to_string/1), else: nil

    with {:ok, items} <- Parquet.parse(path) do
      items = Enum.map(items, &stringify_keys/1)

      items =
        if columns do
          Enum.map(items, &Map.take(&1, columns))
        else
          items
        end

      opts = Keyword.put(opts, :name, name)
      {:ok, from_list(items, opts)}
    end
  end

  @doc """
  Same as `from_parquet/2` but raises on error.
  """
  @spec from_parquet!(Path.t(), keyword()) :: t()
  def from_parquet!(path, opts \\ []) do
    case from_parquet(path, opts) do
      {:ok, dataset} -> dataset
      {:error, error} -> raise RuntimeError, "Failed to load Parquet: #{inspect(error)}"
    end
  end

  @doc """
  Create a dataset from a text file (one line per example).

  ## Options

    * `:column` - Column name for text (default: "text")
    * `:strip` - Strip whitespace from lines (default: true)
    * `:skip_empty` - Skip empty lines (default: true)
    * `:features` - Feature schema
    * `:name` - Dataset name

  ## Examples

      Dataset.from_text("/path/to/data.txt")
      Dataset.from_text("/path/to/data.txt", column: "content")

  """
  @spec from_text(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_text(path, opts \\ []) when is_binary(path) do
    name = Keyword.get(opts, :name, Path.basename(path) |> Path.rootname())
    column = Keyword.get(opts, :column, "text") |> to_string()
    strip = Keyword.get(opts, :strip, true)
    skip_empty = Keyword.get(opts, :skip_empty, true)

    try do
      items =
        path
        |> File.stream!()
        |> Stream.map(fn line ->
          if strip do
            String.trim(line)
          else
            line
            |> String.trim_trailing("\n")
            |> String.trim_trailing("\r")
          end
        end)
        |> Stream.reject(fn line -> skip_empty and line == "" end)
        |> Stream.map(fn line -> %{column => line} end)
        |> Enum.to_list()

      opts = Keyword.put(opts, :name, name)
      {:ok, from_list(items, opts)}
    rescue
      e -> {:error, {:parse_error, e}}
    end
  end

  @doc """
  Same as `from_text/2` but raises on error.
  """
  @spec from_text!(Path.t(), keyword()) :: t()
  def from_text!(path, opts \\ []) do
    case from_text(path, opts) do
      {:ok, dataset} -> dataset
      {:error, error} -> raise RuntimeError, "Failed to load text: #{inspect(error)}"
    end
  end

  @doc """
  Create a dataset from a list of maps.

  ## Options

    * `:name` - Dataset name (default: "dataset")
    * `:version` - Dataset version (default: "1.0")
    * `:metadata` - Dataset metadata map (default: %{})
    * `:features` - Feature schema

  """
  @spec from_list([map()], keyword()) :: t()
  def from_list(items, opts \\ []) when is_list(items) do
    name = Keyword.get(opts, :name, "dataset")
    version = Keyword.get(opts, :version, "1.0")
    metadata = Keyword.get(opts, :metadata, %{})
    features = Keyword.get(opts, :features)

    new(name, version, items, metadata, features)
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
  defp update_items(%__MODULE__{} = dataset, new_items) do
    new_metadata = Map.put(dataset.metadata, :total_items, Kernel.length(new_items))

    %__MODULE__{
      dataset
      | items: new_items,
        metadata: new_metadata,
        fingerprint: nil
    }
  end

  defp maybe_apply_custom_fingerprint(dataset, opts) do
    case Keyword.get(opts, :new_fingerprint) do
      nil -> dataset
      fp -> %{dataset | fingerprint: fp}
    end
  end

  defp apply_transform_fingerprint(dataset, input_fp, transform_fp, opts) do
    new_fp = Keyword.get(opts, :new_fingerprint) || Fingerprint.combine(input_fp, transform_fp)
    %{dataset | fingerprint: new_fp}
  end

  defp caching_enabled? do
    Config.caching_enabled?()
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

    def reduce(%HfDatasetsEx.Dataset{items: items, format: format, format_opts: opts}, acc, fun) do
      formatter = HfDatasetsEx.Formatter.get(format)

      items
      |> Stream.map(&formatter.format_row(&1, opts))
      |> Enumerable.reduce(acc, fun)
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
