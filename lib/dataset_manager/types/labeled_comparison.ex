defmodule HfDatasetsEx.Types.LabeledComparison do
  @moduledoc """
  Represents a preference label for a comparison.

  Used to indicate which response is preferred in a comparison pair.

  ## Fields

    * `:preferred` - Which response is preferred (:a, :b, or :tie)
    * `:margin` - Optional confidence/margin of preference (0.0 to 1.0)

  """

  @type preference :: :a | :b | :tie
  @type t :: %__MODULE__{
          preferred: preference(),
          margin: float() | nil
        }

  @enforce_keys [:preferred]
  defstruct [:preferred, margin: nil]

  @doc """
  Create a new labeled comparison.

  ## Examples

      iex> LabeledComparison.new(:a)
      %LabeledComparison{preferred: :a, margin: nil}

      iex> LabeledComparison.new(:b, 0.8)
      %LabeledComparison{preferred: :b, margin: 0.8}

  """
  @spec new(preference(), float() | nil) :: t()
  def new(preferred, margin \\ nil) when preferred in [:a, :b, :tie] do
    %__MODULE__{
      preferred: preferred,
      margin: margin
    }
  end

  @doc """
  Parse a preference label from string.

  ## Examples

      iex> LabeledComparison.from_label("A")
      {:ok, %LabeledComparison{preferred: :a}}

      iex> LabeledComparison.from_label("chosen")
      {:ok, %LabeledComparison{preferred: :a}}

  """
  @spec from_label(String.t() | atom()) :: {:ok, t()} | {:error, term()}
  def from_label(label) when is_binary(label) do
    case String.downcase(String.trim(label)) do
      "a" -> {:ok, new(:a)}
      "b" -> {:ok, new(:b)}
      "tie" -> {:ok, new(:tie)}
      "chosen" -> {:ok, new(:a)}
      "rejected" -> {:ok, new(:b)}
      "model_a" -> {:ok, new(:a)}
      "model_b" -> {:ok, new(:b)}
      _ -> {:error, {:invalid_label, label}}
    end
  end

  def from_label(:a), do: {:ok, new(:a)}
  def from_label(:b), do: {:ok, new(:b)}
  def from_label(:tie), do: {:ok, new(:tie)}
  def from_label(_), do: {:error, :invalid_label}

  @doc """
  Create a preference from HH-RLHF format (where chosen is always preferred).
  """
  @spec from_hh_rlhf() :: t()
  def from_hh_rlhf do
    # In HH-RLHF, "chosen" is always response_a (preferred)
    new(:a)
  end

  @doc """
  Check if a response is the preferred one.
  """
  @spec preferred?(t(), :a | :b) :: boolean()
  def preferred?(%__MODULE__{preferred: preferred}, response) do
    preferred == response
  end

  @doc """
  Get the winning response indicator (1 for a, 0 for b, 0.5 for tie).
  Useful for loss calculation.
  """
  @spec to_score(t()) :: float()
  def to_score(%__MODULE__{preferred: :a}), do: 1.0
  def to_score(%__MODULE__{preferred: :b}), do: 0.0
  def to_score(%__MODULE__{preferred: :tie}), do: 0.5
end
