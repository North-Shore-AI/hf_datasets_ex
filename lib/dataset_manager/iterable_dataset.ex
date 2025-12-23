defmodule HfDatasetsEx.IterableDataset do
  @moduledoc """
  A lazy, streaming dataset for memory-efficient processing.

  IterableDataset wraps a Stream and provides lazy transformations
  that are only evaluated when items are consumed. This is ideal for
  processing large datasets that don't fit in memory.

  ## Example

      # Create from stream
      iterable = IterableDataset.from_stream(file_stream, name: "large_dataset")

      # Chain lazy operations
      processed =
        iterable
        |> IterableDataset.filter(&(&1.score > 0.5))
        |> IterableDataset.map(&process_item/1)
        |> IterableDataset.batch(32)

      # Consume lazily
      for batch <- processed do
        train_on_batch(batch)
      end

  ## Comparison with Dataset

  - `Dataset`: Eager, in-memory, fast random access
  - `IterableDataset`: Lazy, streaming, memory-efficient

  Use IterableDataset when:
  - Dataset is too large for memory
  - You only need to iterate once
  - Processing can be done in batches
  """

  alias HfDatasetsEx.Dataset

  @type t :: %__MODULE__{
          stream: Enumerable.t(),
          name: String.t(),
          info: map()
        }

  @enforce_keys [:stream, :name]
  defstruct [:stream, :name, info: %{}]

  @doc """
  Create an IterableDataset from an enumerable/stream.

  ## Options

    * `:name` - Name for the dataset (required)

  ## Example

      IterableDataset.from_stream(file_stream, name: "my_dataset")

  """
  @spec from_stream(Enumerable.t(), keyword()) :: t()
  def from_stream(stream, opts) do
    name = Keyword.fetch!(opts, :name)

    %__MODULE__{
      stream: stream,
      name: name,
      info: Keyword.get(opts, :info, %{})
    }
  end

  @doc """
  Convert a Dataset to an IterableDataset.

  This wraps the dataset's items in a stream for lazy processing.

  ## Example

      iterable = IterableDataset.from_dataset(dataset)

  """
  @spec from_dataset(Dataset.t()) :: t()
  def from_dataset(%Dataset{} = dataset) do
    %__MODULE__{
      stream: Stream.map(dataset.items, & &1),
      name: dataset.name,
      info: dataset.metadata
    }
  end

  @doc """
  Take the first N items from the stream.

  Returns a list (materializes the taken items).

  ## Example

      items = IterableDataset.take(iterable, 10)

  """
  @spec take(t(), non_neg_integer()) :: [map()]
  def take(%__MODULE__{stream: stream}, count) do
    Enum.take(stream, count)
  end

  @doc """
  Skip the first N items and return a new IterableDataset.

  ## Example

      rest = IterableDataset.skip(iterable, 100)

  """
  @spec skip(t(), non_neg_integer()) :: t()
  def skip(%__MODULE__{} = iterable, count) do
    new_stream = Stream.drop(iterable.stream, count)
    %{iterable | stream: new_stream}
  end

  @doc """
  Lazily transform each item.

  ## Example

      transformed = IterableDataset.map(iterable, fn item ->
        Map.put(item, :processed, true)
      end)

  """
  @spec map(t(), (map() -> map())) :: t()
  def map(%__MODULE__{} = iterable, fun) when is_function(fun, 1) do
    new_stream = Stream.map(iterable.stream, fun)
    %{iterable | stream: new_stream}
  end

  @doc """
  Lazily filter items.

  ## Example

      filtered = IterableDataset.filter(iterable, fn item ->
        item.score > 0.5
      end)

  """
  @spec filter(t(), (map() -> boolean())) :: t()
  def filter(%__MODULE__{} = iterable, fun) when is_function(fun, 1) do
    new_stream = Stream.filter(iterable.stream, fun)
    %{iterable | stream: new_stream}
  end

  @doc """
  Group items into batches.

  Returns an IterableDataset of lists.

  ## Example

      batched = IterableDataset.batch(iterable, 32)
      for batch <- batched do
        # batch is a list of 32 items
      end

  """
  @spec batch(t(), pos_integer()) :: t()
  def batch(%__MODULE__{} = iterable, size) when is_integer(size) and size > 0 do
    new_stream = Stream.chunk_every(iterable.stream, size)
    %{iterable | stream: new_stream}
  end

  @doc """
  Shuffle items using a buffer.

  Since streaming datasets can't be fully shuffled in memory,
  this uses a buffer to shuffle items as they stream through.

  ## Options

    * `:buffer_size` - Size of shuffle buffer (required)
    * `:seed` - Random seed for reproducibility

  ## Example

      shuffled = IterableDataset.shuffle(iterable, buffer_size: 1000)

  """
  @spec shuffle(t(), keyword()) :: t()
  def shuffle(%__MODULE__{} = iterable, opts) do
    buffer_size = Keyword.fetch!(opts, :buffer_size)
    seed = Keyword.get(opts, :seed)

    new_stream =
      iterable.stream
      |> buffer_shuffle(buffer_size, seed)

    %{iterable | stream: new_stream}
  end

  defp buffer_shuffle(stream, buffer_size, seed) do
    Stream.resource(
      fn ->
        if seed, do: :rand.seed(:exsss, {seed, seed, seed})
        {stream, []}
      end,
      fn {remaining_stream, buffer} ->
        # Try to fill buffer
        case Enum.take(remaining_stream, max(0, buffer_size - length(buffer))) do
          [] when buffer == [] ->
            {:halt, nil}

          [] ->
            # No more items, flush buffer
            shuffled = Enum.shuffle(buffer)
            {shuffled, {[], []}}

          new_items ->
            new_buffer = buffer ++ new_items
            shuffled = Enum.shuffle(new_buffer)
            # Emit one item, keep rest in buffer
            {emit, keep} = Enum.split(shuffled, 1)
            new_remaining = Stream.drop(remaining_stream, length(new_items))
            {emit, {new_remaining, keep}}
        end
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Materialize the stream to a list.

  Caution: This loads all items into memory.

  ## Example

      items = IterableDataset.to_list(iterable)

  """
  @spec to_list(t()) :: [map()]
  def to_list(%__MODULE__{stream: stream}) do
    Enum.to_list(stream)
  end

  @doc """
  Materialize the stream to a Dataset struct.

  Caution: This loads all items into memory.

  ## Example

      dataset = IterableDataset.to_dataset(iterable)

  """
  @spec to_dataset(t()) :: Dataset.t()
  def to_dataset(%__MODULE__{} = iterable) do
    items = to_list(iterable)
    Dataset.new(iterable.name, "1.0", items, iterable.info)
  end

  @doc """
  Add metadata to the iterable.

  ## Example

      iterable = IterableDataset.with_info(iterable, %{source: "hf"})

  """
  @spec with_info(t(), map()) :: t()
  def with_info(%__MODULE__{} = iterable, info) when is_map(info) do
    %{iterable | info: Map.merge(iterable.info, info)}
  end

  # ===========================================================================
  # Enumerable Protocol
  # ===========================================================================

  defimpl Enumerable do
    def count(_iterable) do
      {:error, __MODULE__}
    end

    def member?(_iterable, _element) do
      {:error, __MODULE__}
    end

    def slice(_iterable) do
      {:error, __MODULE__}
    end

    def reduce(iterable, acc, fun) do
      Enumerable.reduce(iterable.stream, acc, fun)
    end
  end
end
