defmodule HfDatasetsEx.Features.Sequence do
  @moduledoc """
  Sequence (list) feature type.

  Represents a list of values of a single type.

  ## Example

      # List of strings
      Sequence.new(Value.string())

      # List of integers
      Sequence.new(Value.int32())

      # List of floats with fixed length
      Sequence.new(Value.float32(), length: 768)

      # Nested sequences
      Sequence.new(Sequence.new(Value.int32()))

  """

  alias HfDatasetsEx.Features.Value

  @type t :: %__MODULE__{
          feature: HfDatasetsEx.Features.feature_type(),
          length: non_neg_integer() | nil
        }

  @enforce_keys [:feature]
  defstruct [:feature, :length]

  @doc """
  Create a new Sequence type.

  ## Arguments

    * `feature` - The type of elements in the sequence
    * `opts` - Options:
      * `:length` - Fixed length (optional)

  """
  @spec new(HfDatasetsEx.Features.feature_type(), keyword()) :: t()
  def new(feature, opts \\ []) do
    %__MODULE__{
      feature: feature,
      length: Keyword.get(opts, :length)
    }
  end

  @doc "Create a sequence of strings"
  @spec of_strings() :: t()
  def of_strings, do: new(Value.string())

  @doc "Create a sequence of integers"
  @spec of_integers() :: t()
  def of_integers, do: new(Value.int64())

  @doc "Create a sequence of floats"
  @spec of_floats() :: t()
  def of_floats, do: new(Value.float64())

  @doc "Create a fixed-length sequence (e.g., for embeddings)"
  @spec fixed(HfDatasetsEx.Features.feature_type(), non_neg_integer()) :: t()
  def fixed(feature, length), do: new(feature, length: length)
end
