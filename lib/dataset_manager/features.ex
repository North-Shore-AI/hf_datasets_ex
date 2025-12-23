defmodule HfDatasetsEx.Features do
  @moduledoc """
  Schema system for dataset columns.

  Features define the types and structure of dataset columns, similar to
  HuggingFace datasets' Features system.

  ## Feature Types

    * `Value` - Scalar values (int, float, string, bool, binary)
    * `ClassLabel` - Categorical labels with names
    * `Sequence` - Lists of a single type
    * `Image` - Image data with optional decode
    * `Audio` - Audio data with sample rate
    * `Translation` - Parallel text in multiple languages
    * `Dict` - Nested dictionary structure

  ## Example

      features = Features.new(%{
        "id" => Value.string(),
        "text" => Value.string(),
        "label" => ClassLabel.new(names: ["positive", "negative"]),
        "embeddings" => Sequence.new(Value.float32())
      })

      # Validate dataset against features
      {:ok, validated} = Features.validate(dataset, features)

      # Cast values to match schema
      {:ok, casted} = Features.cast(dataset, features)

  """

  alias HfDatasetsEx.Features.{Value, ClassLabel, Sequence, Image, Audio}
  alias HfDatasetsEx.Media.Image, as: ImageDecoder

  @type feature_type ::
          Value.t()
          | ClassLabel.t()
          | Sequence.t()
          | Image.t()
          | Audio.t()
          | {:dict, %{String.t() => feature_type()}}

  @type t :: %__MODULE__{
          schema: %{String.t() => feature_type()}
        }

  @enforce_keys [:schema]
  defstruct [:schema]

  @doc """
  Create a new Features schema.

  ## Example

      features = Features.new(%{
        "id" => Value.string(),
        "text" => Value.string(),
        "score" => Value.float32()
      })

  """
  @spec new(%{String.t() => feature_type()}) :: t()
  def new(schema) when is_map(schema) do
    %__MODULE__{schema: schema}
  end

  @doc """
  Get the feature type for a column.
  """
  @spec get(t(), String.t()) :: feature_type() | nil
  def get(%__MODULE__{schema: schema}, column) do
    Map.get(schema, column)
  end

  @doc """
  Get all column names.
  """
  @spec column_names(t()) :: [String.t()]
  def column_names(%__MODULE__{schema: schema}) do
    Map.keys(schema)
  end

  @doc """
  Validate a value against a feature type.
  """
  @spec validate_value(any(), feature_type()) :: {:ok, any()} | {:error, term()}
  def validate_value(value, %Value{dtype: dtype}) do
    case validate_dtype(value, dtype) do
      true -> {:ok, value}
      false -> {:error, {:type_mismatch, expected: dtype, got: typeof(value)}}
    end
  end

  def validate_value(value, %ClassLabel{names: names}) when is_integer(value) do
    if value >= 0 and value < length(names) do
      {:ok, value}
    else
      {:error, {:invalid_class_index, value, length(names)}}
    end
  end

  def validate_value(value, %ClassLabel{names: names}) when is_binary(value) do
    if value in names do
      {:ok, Enum.find_index(names, &(&1 == value))}
    else
      {:error, {:unknown_class, value}}
    end
  end

  def validate_value(value, %Sequence{feature: inner}) when is_list(value) do
    results = Enum.map(value, &validate_value(&1, inner))
    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      {:ok, Enum.map(results, fn {:ok, v} -> v end)}
    else
      {:error, {:sequence_errors, errors}}
    end
  end

  def validate_value(value, %Image{}) when is_binary(value), do: {:ok, value}

  def validate_value(%{"bytes" => bytes} = value, %Image{}) when is_binary(bytes),
    do: {:ok, value}

  def validate_value(%{"path" => path} = value, %Image{}) when is_binary(path), do: {:ok, value}

  def validate_value(value, %Audio{}) when is_binary(value), do: {:ok, value}

  def validate_value(%{"bytes" => bytes} = value, %Audio{}) when is_binary(bytes),
    do: {:ok, value}

  def validate_value(%{"path" => path} = value, %Audio{}) when is_binary(path), do: {:ok, value}

  def validate_value(value, {:dict, inner_schema}) when is_map(value) do
    results =
      Enum.map(inner_schema, fn {key, feature_type} ->
        case Map.fetch(value, key) do
          {:ok, v} ->
            case validate_value(v, feature_type) do
              {:ok, validated} -> {:ok, {key, validated}}
              error -> error
            end

          :error ->
            {:error, {:missing_key, key}}
        end
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      {:ok, Map.new(Enum.map(results, fn {:ok, kv} -> kv end))}
    else
      {:error, {:dict_errors, errors}}
    end
  end

  def validate_value(_value, _type), do: {:error, :invalid_type}

  @doc """
  Validate a dataset item against the features schema.
  """
  @spec validate_item(map(), t()) :: {:ok, map()} | {:error, term()}
  def validate_item(item, %__MODULE__{schema: schema}) do
    results =
      Enum.map(schema, fn {column, feature_type} ->
        case Map.fetch(item, column) do
          {:ok, value} ->
            case validate_value(value, feature_type) do
              {:ok, validated} -> {:ok, {column, validated}}
              {:error, reason} -> {:error, {column, reason}}
            end

          :error ->
            # Try atom key
            case Map.fetch(item, String.to_atom(column)) do
              {:ok, value} ->
                case validate_value(value, feature_type) do
                  {:ok, validated} -> {:ok, {column, validated}}
                  {:error, reason} -> {:error, {column, reason}}
                end

              :error ->
                {:error, {column, :missing}}
            end
        end
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      {:ok, Map.new(Enum.map(results, fn {:ok, kv} -> kv end))}
    else
      {:error, {:validation_errors, Enum.map(errors, fn {:error, e} -> e end)}}
    end
  end

  @doc """
  Cast a value to match a feature type.
  """
  @spec cast_value(any(), feature_type()) :: {:ok, any()} | {:error, term()}
  def cast_value(value, %Value{dtype: dtype}) do
    cast_to_dtype(value, dtype)
  end

  def cast_value(value, %ClassLabel{names: names}) when is_binary(value) do
    case Enum.find_index(names, &(&1 == value)) do
      nil -> {:error, {:unknown_class, value}}
      idx -> {:ok, idx}
    end
  end

  def cast_value(value, %ClassLabel{} = cl) when is_integer(value) do
    validate_value(value, cl)
  end

  def cast_value(value, %Sequence{feature: inner}) when is_list(value) do
    results = Enum.map(value, &cast_value(&1, inner))
    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      {:ok, Enum.map(results, fn {:ok, v} -> v end)}
    else
      {:error, {:sequence_cast_errors, errors}}
    end
  end

  def cast_value(value, type), do: validate_value(value, type)

  @doc """
  Infer features from a dataset.
  """
  @spec infer(HfDatasetsEx.Dataset.t()) :: t()
  def infer(dataset) do
    infer_from_items(dataset.items)
  end

  @doc """
  Infer features from a list of dataset items.
  """
  @spec infer_from_items([map()]) :: t()
  def infer_from_items([]), do: new(%{})

  def infer_from_items([first | _]) do
    schema =
      first
      |> Enum.map(fn {key, value} ->
        key_str = if is_atom(key), do: Atom.to_string(key), else: key
        {key_str, infer_type(value)}
      end)
      |> Map.new()

    new(schema)
  end

  @doc """
  Decode a dataset item based on the feature schema.
  """
  @spec decode_item(map(), t()) :: map()
  def decode_item(item, %__MODULE__{schema: schema}) do
    Enum.reduce(schema, item, fn {column, feature}, acc ->
      key = if Map.has_key?(acc, column), do: column, else: String.to_atom(column)

      case Map.fetch(acc, key) do
        {:ok, value} ->
          case decode_value(value, feature) do
            {:ok, decoded} -> Map.put(acc, key, decoded)
            _ -> acc
          end

        :error ->
          acc
      end
    end)
  end

  defp decode_value(value, %Image{decode: false}), do: {:ok, value}

  defp decode_value(%{"bytes" => bytes}, %Image{} = image) when is_binary(bytes) do
    ImageDecoder.decode(bytes, mode: image.mode)
  end

  defp decode_value(%{"path" => path}, %Image{} = image) when is_binary(path) do
    ImageDecoder.decode_file(path, mode: image.mode)
  end

  defp decode_value(value, {:dict, inner_schema}) when is_map(value) do
    decoded =
      Enum.reduce(inner_schema, value, fn {key, feature}, acc ->
        case Map.fetch(acc, key) do
          {:ok, inner_value} ->
            case decode_value(inner_value, feature) do
              {:ok, inner_decoded} -> Map.put(acc, key, inner_decoded)
              _ -> acc
            end

          :error ->
            acc
        end
      end)

    {:ok, decoded}
  end

  defp decode_value(value, _feature), do: {:ok, value}

  defp infer_type(value) when is_binary(value), do: Value.string()
  defp infer_type(value) when is_integer(value), do: Value.int64()
  defp infer_type(value) when is_float(value), do: Value.float64()
  defp infer_type(value) when is_boolean(value), do: Value.bool()

  defp infer_type(value) when is_list(value) do
    case value do
      [] -> Sequence.new(Value.string())
      [first | _] -> Sequence.new(infer_type(first))
    end
  end

  defp infer_type(value) when is_struct(value) do
    value
    |> Map.from_struct()
    |> infer_type()
  end

  defp infer_type(value) when is_map(value) do
    inner =
      value
      |> Enum.map(fn {k, v} ->
        key_str = if is_atom(k), do: Atom.to_string(k), else: k
        {key_str, infer_type(v)}
      end)
      |> Map.new()

    {:dict, inner}
  end

  defp infer_type(_), do: Value.string()

  # Helpers

  defp validate_dtype(value, :string) when is_binary(value), do: true
  defp validate_dtype(value, :int8) when is_integer(value), do: value >= -128 and value <= 127

  defp validate_dtype(value, :int16) when is_integer(value),
    do: value >= -32768 and value <= 32767

  defp validate_dtype(value, :int32) when is_integer(value), do: true
  defp validate_dtype(value, :int64) when is_integer(value), do: true
  defp validate_dtype(value, :uint8) when is_integer(value), do: value >= 0 and value <= 255
  defp validate_dtype(value, :uint16) when is_integer(value), do: value >= 0 and value <= 65535
  defp validate_dtype(value, :uint32) when is_integer(value), do: value >= 0
  defp validate_dtype(value, :uint64) when is_integer(value), do: value >= 0
  defp validate_dtype(value, :float16) when is_float(value), do: true
  defp validate_dtype(value, :float32) when is_float(value), do: true
  defp validate_dtype(value, :float64) when is_float(value), do: true
  defp validate_dtype(value, :bool) when is_boolean(value), do: true
  defp validate_dtype(value, :binary) when is_binary(value), do: true
  defp validate_dtype(_, _), do: false

  defp cast_to_dtype(value, :string) when is_binary(value), do: {:ok, value}
  defp cast_to_dtype(value, :string), do: {:ok, to_string(value)}
  defp cast_to_dtype(value, :int64) when is_integer(value), do: {:ok, value}
  defp cast_to_dtype(value, :int64) when is_float(value), do: {:ok, trunc(value)}
  defp cast_to_dtype(value, :int64) when is_binary(value), do: parse_int(value)
  defp cast_to_dtype(value, :float64) when is_float(value), do: {:ok, value}
  defp cast_to_dtype(value, :float64) when is_integer(value), do: {:ok, value / 1}
  defp cast_to_dtype(value, :float64) when is_binary(value), do: parse_float(value)
  defp cast_to_dtype(value, :bool) when is_boolean(value), do: {:ok, value}
  defp cast_to_dtype("true", :bool), do: {:ok, true}
  defp cast_to_dtype("false", :bool), do: {:ok, false}
  defp cast_to_dtype(1, :bool), do: {:ok, true}
  defp cast_to_dtype(0, :bool), do: {:ok, false}
  defp cast_to_dtype(value, type), do: {:error, {:cannot_cast, value, type}}

  defp parse_int(str) do
    case Integer.parse(str) do
      {i, ""} -> {:ok, i}
      _ -> {:error, {:invalid_int, str}}
    end
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {f, ""} -> {:ok, f}
      _ -> {:error, {:invalid_float, str}}
    end
  end

  defp typeof(v) when is_binary(v), do: :string
  defp typeof(v) when is_integer(v), do: :integer
  defp typeof(v) when is_float(v), do: :float
  defp typeof(v) when is_boolean(v), do: :bool
  defp typeof(v) when is_list(v), do: :list
  defp typeof(v) when is_map(v), do: :map
  defp typeof(_), do: :unknown
end
