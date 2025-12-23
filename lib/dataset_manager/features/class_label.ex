defmodule HfDatasetsEx.Features.ClassLabel do
  @moduledoc """
  Categorical label feature type.

  Represents classification labels with a fixed set of class names.
  Values are stored as integers (class indices) but can be decoded
  to their string names.

  ## Example

      # Binary classification
      ClassLabel.new(names: ["negative", "positive"])

      # Multi-class
      ClassLabel.new(names: ["cat", "dog", "bird", "fish"])

      # From number of classes
      ClassLabel.new(num_classes: 10)

  """

  @type t :: %__MODULE__{
          names: [String.t()],
          num_classes: non_neg_integer()
        }

  @enforce_keys [:names, :num_classes]
  defstruct [:names, :num_classes]

  @doc """
  Create a new ClassLabel.

  ## Options

    * `:names` - List of class names
    * `:num_classes` - Number of classes (if names not provided)

  """
  @spec new(keyword()) :: t()
  def new(opts) do
    names = Keyword.get(opts, :names, [])
    num_classes = Keyword.get(opts, :num_classes, length(names))

    # Generate default names if not provided
    final_names =
      if names == [] and num_classes > 0 do
        Enum.map(0..(num_classes - 1), &"class_#{&1}")
      else
        names
      end

    %__MODULE__{
      names: final_names,
      num_classes: length(final_names)
    }
  end

  @doc "Get the class name for an index"
  @spec int2str(t(), non_neg_integer()) :: String.t() | nil
  def int2str(%__MODULE__{names: names}, idx) when is_integer(idx) do
    Enum.at(names, idx)
  end

  @doc "Get the index for a class name"
  @spec str2int(t(), String.t()) :: non_neg_integer() | nil
  def str2int(%__MODULE__{names: names}, name) when is_binary(name) do
    Enum.find_index(names, &(&1 == name))
  end

  @doc "Decode integer labels to string names"
  @spec decode(t(), [non_neg_integer()]) :: [String.t()]
  def decode(%__MODULE__{} = cl, labels) when is_list(labels) do
    Enum.map(labels, &int2str(cl, &1))
  end

  @doc "Encode string names to integer labels"
  @spec encode(t(), [String.t()]) :: [non_neg_integer()]
  def encode(%__MODULE__{} = cl, names) when is_list(names) do
    Enum.map(names, &str2int(cl, &1))
  end
end
