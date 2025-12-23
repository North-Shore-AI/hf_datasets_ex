defmodule HfDatasetsEx.Features.Value do
  @moduledoc """
  Scalar value feature type.

  Represents primitive types like integers, floats, strings, and booleans.

  ## Supported Data Types

    * `:int8`, `:int16`, `:int32`, `:int64` - Signed integers
    * `:uint8`, `:uint16`, `:uint32`, `:uint64` - Unsigned integers
    * `:float16`, `:float32`, `:float64` - Floating point
    * `:bool` - Boolean
    * `:string` - String/text
    * `:binary` - Raw bytes

  ## Example

      Value.string()
      Value.int64()
      Value.float32()
      Value.new(:int32)

  """

  @type dtype ::
          :int8
          | :int16
          | :int32
          | :int64
          | :uint8
          | :uint16
          | :uint32
          | :uint64
          | :float16
          | :float32
          | :float64
          | :bool
          | :string
          | :binary

  @type t :: %__MODULE__{
          dtype: dtype()
        }

  @enforce_keys [:dtype]
  defstruct [:dtype]

  @doc "Create a new Value with the given dtype"
  @spec new(dtype()) :: t()
  def new(dtype), do: %__MODULE__{dtype: dtype}

  @doc "String type"
  @spec string() :: t()
  def string, do: new(:string)

  @doc "8-bit signed integer"
  @spec int8() :: t()
  def int8, do: new(:int8)

  @doc "16-bit signed integer"
  @spec int16() :: t()
  def int16, do: new(:int16)

  @doc "32-bit signed integer"
  @spec int32() :: t()
  def int32, do: new(:int32)

  @doc "64-bit signed integer"
  @spec int64() :: t()
  def int64, do: new(:int64)

  @doc "8-bit unsigned integer"
  @spec uint8() :: t()
  def uint8, do: new(:uint8)

  @doc "16-bit unsigned integer"
  @spec uint16() :: t()
  def uint16, do: new(:uint16)

  @doc "32-bit unsigned integer"
  @spec uint32() :: t()
  def uint32, do: new(:uint32)

  @doc "64-bit unsigned integer"
  @spec uint64() :: t()
  def uint64, do: new(:uint64)

  @doc "16-bit float (half precision)"
  @spec float16() :: t()
  def float16, do: new(:float16)

  @doc "32-bit float (single precision)"
  @spec float32() :: t()
  def float32, do: new(:float32)

  @doc "64-bit float (double precision)"
  @spec float64() :: t()
  def float64, do: new(:float64)

  @doc "Boolean"
  @spec bool() :: t()
  def bool, do: new(:bool)

  @doc "Raw binary"
  @spec binary() :: t()
  def binary, do: new(:binary)
end
