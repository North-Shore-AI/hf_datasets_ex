defmodule HfDatasetsEx.Features.Array2D do
  @moduledoc """
  A 2-dimensional array feature type.

  ## Examples

      # 28x28 grayscale image
      %Array2D{shape: {28, 28}, dtype: :float32}

      # 100x768 embedding matrix
      %Array2D{shape: {100, 768}, dtype: :float32}

  """

  alias HfDatasetsEx.Features.Value

  @type t :: %__MODULE__{
          shape: {non_neg_integer(), non_neg_integer()},
          dtype: atom()
        }

  @enforce_keys [:shape, :dtype]
  defstruct [:shape, :dtype]

  @spec new({non_neg_integer(), non_neg_integer()}, atom()) :: t()
  def new(shape, dtype \\ :float32) do
    %__MODULE__{shape: shape, dtype: dtype}
  end

  @doc """
  Validate that a value matches this Array2D spec.
  """
  @spec validate(any(), t()) :: {:ok, any()} | {:error, term()}
  def validate(value, %__MODULE__{shape: {rows, cols}, dtype: _dtype}) when is_list(value) do
    valid =
      length(value) == rows and
        Enum.all?(value, fn row ->
          is_list(row) and length(row) == cols and Enum.all?(row, &(not is_list(&1)))
        end)

    if valid do
      {:ok, value}
    else
      {:error, {:shape_mismatch, expected: {rows, cols}, got: infer_shape(value)}}
    end
  end

  def validate(%Nx.Tensor{} = tensor, %__MODULE__{shape: shape, dtype: _dtype}) do
    if Nx.shape(tensor) == shape do
      {:ok, tensor}
    else
      {:error, {:shape_mismatch, expected: shape, got: Nx.shape(tensor)}}
    end
  end

  def validate(value, _spec), do: {:error, {:invalid_type, value}}

  @doc """
  Convert value to Nx tensor with correct shape and type.
  """
  @spec to_nx(any(), t()) :: Nx.Tensor.t()
  def to_nx(value, %__MODULE__{shape: shape, dtype: dtype}) when is_list(value) do
    Nx.tensor(value, type: Value.dtype_to_nx(dtype))
    |> Nx.reshape(shape)
  end

  def to_nx(%Nx.Tensor{} = tensor, %__MODULE__{shape: shape, dtype: dtype}) do
    tensor
    |> Nx.as_type(Value.dtype_to_nx(dtype))
    |> Nx.reshape(shape)
  end

  defp infer_shape(value) when is_list(value) do
    rows = length(value)
    cols = if rows > 0 and is_list(hd(value)), do: length(hd(value)), else: 0
    {rows, cols}
  end
end

defmodule HfDatasetsEx.Features.Array3D do
  @moduledoc """
  A 3-dimensional array feature type.

  ## Examples

      # RGB image: height x width x channels
      %Array3D{shape: {224, 224, 3}, dtype: :uint8}

      # Audio spectrogram: time x frequency x channels
      %Array3D{shape: {100, 128, 1}, dtype: :float32}

  """

  alias HfDatasetsEx.Features.Value

  @type t :: %__MODULE__{
          shape: {non_neg_integer(), non_neg_integer(), non_neg_integer()},
          dtype: atom()
        }

  @enforce_keys [:shape, :dtype]
  defstruct [:shape, :dtype]

  @spec new(tuple(), atom()) :: t()
  def new(shape, dtype \\ :float32) when tuple_size(shape) == 3 do
    %__MODULE__{shape: shape, dtype: dtype}
  end

  @spec validate(any(), t()) :: {:ok, any()} | {:error, term()}
  def validate(%Nx.Tensor{} = tensor, %__MODULE__{shape: shape}) do
    if Nx.shape(tensor) == shape do
      {:ok, tensor}
    else
      {:error, {:shape_mismatch, expected: shape, got: Nx.shape(tensor)}}
    end
  end

  def validate(value, %__MODULE__{shape: shape}) when is_list(value) do
    if list_shape_matches?(value, Tuple.to_list(shape)) do
      {:ok, value}
    else
      {:error, {:shape_mismatch, expected: shape, got: infer_shape(value)}}
    end
  end

  def validate(value, _spec), do: {:error, {:invalid_type, value}}

  @spec to_nx(any(), t()) :: Nx.Tensor.t()
  def to_nx(value, %__MODULE__{shape: shape, dtype: dtype}) when is_list(value) do
    Nx.tensor(value, type: Value.dtype_to_nx(dtype))
    |> Nx.reshape(shape)
  end

  def to_nx(%Nx.Tensor{} = tensor, %__MODULE__{shape: shape, dtype: dtype}) do
    tensor
    |> Nx.as_type(Value.dtype_to_nx(dtype))
    |> Nx.reshape(shape)
  end

  defp list_shape_matches?(value, []), do: not is_list(value)

  defp list_shape_matches?(value, [dim | rest]) when is_list(value) do
    length(value) == dim and Enum.all?(value, &list_shape_matches?(&1, rest))
  end

  defp list_shape_matches?(_value, _shape), do: false

  defp infer_shape(value) when is_list(value) do
    value
    |> list_shape()
    |> List.to_tuple()
  end

  defp list_shape([]), do: [0]

  defp list_shape(value) when is_list(value) do
    case value do
      [] -> [0]
      [first | _] -> [length(value) | list_shape(first)]
    end
  end

  defp list_shape(_), do: []
end

defmodule HfDatasetsEx.Features.Array4D do
  @moduledoc """
  A 4-dimensional array feature type.

  ## Examples

      # Video frames: frames x height x width x channels
      %Array4D{shape: {16, 224, 224, 3}, dtype: :uint8}

  """

  alias HfDatasetsEx.Features.Value

  @type t :: %__MODULE__{
          shape: {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()},
          dtype: atom()
        }

  @enforce_keys [:shape, :dtype]
  defstruct [:shape, :dtype]

  @spec new(tuple(), atom()) :: t()
  def new(shape, dtype \\ :float32) when tuple_size(shape) == 4 do
    %__MODULE__{shape: shape, dtype: dtype}
  end

  @spec validate(any(), t()) :: {:ok, any()} | {:error, term()}
  def validate(%Nx.Tensor{} = tensor, %__MODULE__{shape: shape}) do
    if Nx.shape(tensor) == shape do
      {:ok, tensor}
    else
      {:error, {:shape_mismatch, expected: shape, got: Nx.shape(tensor)}}
    end
  end

  def validate(value, %__MODULE__{shape: shape}) when is_list(value) do
    if list_shape_matches?(value, Tuple.to_list(shape)) do
      {:ok, value}
    else
      {:error, {:shape_mismatch, expected: shape, got: infer_shape(value)}}
    end
  end

  def validate(value, _spec), do: {:error, {:invalid_type, value}}

  @spec to_nx(any(), t()) :: Nx.Tensor.t()
  def to_nx(value, %__MODULE__{shape: shape, dtype: dtype}) when is_list(value) do
    Nx.tensor(value, type: Value.dtype_to_nx(dtype))
    |> Nx.reshape(shape)
  end

  def to_nx(%Nx.Tensor{} = tensor, %__MODULE__{shape: shape, dtype: dtype}) do
    tensor
    |> Nx.as_type(Value.dtype_to_nx(dtype))
    |> Nx.reshape(shape)
  end

  defp list_shape_matches?(value, []), do: not is_list(value)

  defp list_shape_matches?(value, [dim | rest]) when is_list(value) do
    length(value) == dim and Enum.all?(value, &list_shape_matches?(&1, rest))
  end

  defp list_shape_matches?(_value, _shape), do: false

  defp infer_shape(value) when is_list(value) do
    value
    |> list_shape()
    |> List.to_tuple()
  end

  defp list_shape([]), do: [0]

  defp list_shape(value) when is_list(value) do
    case value do
      [] -> [0]
      [first | _] -> [length(value) | list_shape(first)]
    end
  end

  defp list_shape(_), do: []
end

defmodule HfDatasetsEx.Features.Array5D do
  @moduledoc """
  A 5-dimensional array feature type.

  ## Examples

      # Batched video: batch x frames x height x width x channels
      %Array5D{shape: {8, 16, 224, 224, 3}, dtype: :uint8}

  """

  alias HfDatasetsEx.Features.Value

  @type t :: %__MODULE__{
          shape: tuple(),
          dtype: atom()
        }

  @enforce_keys [:shape, :dtype]
  defstruct [:shape, :dtype]

  @spec new(tuple(), atom()) :: t()
  def new(shape, dtype \\ :float32) when tuple_size(shape) == 5 do
    %__MODULE__{shape: shape, dtype: dtype}
  end

  @spec validate(any(), t()) :: {:ok, any()} | {:error, term()}
  def validate(%Nx.Tensor{} = tensor, %__MODULE__{shape: shape}) do
    if Nx.shape(tensor) == shape do
      {:ok, tensor}
    else
      {:error, {:shape_mismatch, expected: shape, got: Nx.shape(tensor)}}
    end
  end

  def validate(value, %__MODULE__{shape: shape}) when is_list(value) do
    if list_shape_matches?(value, Tuple.to_list(shape)) do
      {:ok, value}
    else
      {:error, {:shape_mismatch, expected: shape, got: infer_shape(value)}}
    end
  end

  def validate(value, _spec), do: {:error, {:invalid_type, value}}

  @spec to_nx(any(), t()) :: Nx.Tensor.t()
  def to_nx(value, %__MODULE__{shape: shape, dtype: dtype}) when is_list(value) do
    Nx.tensor(value, type: Value.dtype_to_nx(dtype))
    |> Nx.reshape(shape)
  end

  def to_nx(%Nx.Tensor{} = tensor, %__MODULE__{shape: shape, dtype: dtype}) do
    tensor
    |> Nx.as_type(Value.dtype_to_nx(dtype))
    |> Nx.reshape(shape)
  end

  defp list_shape_matches?(value, []), do: not is_list(value)

  defp list_shape_matches?(value, [dim | rest]) when is_list(value) do
    length(value) == dim and Enum.all?(value, &list_shape_matches?(&1, rest))
  end

  defp list_shape_matches?(_value, _shape), do: false

  defp infer_shape(value) when is_list(value) do
    value
    |> list_shape()
    |> List.to_tuple()
  end

  defp list_shape([]), do: [0]

  defp list_shape(value) when is_list(value) do
    case value do
      [] -> [0]
      [first | _] -> [length(value) | list_shape(first)]
    end
  end

  defp list_shape(_), do: []
end
