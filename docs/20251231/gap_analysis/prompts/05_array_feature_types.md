# Implementation Prompt: Array Feature Types

## Priority: P1 (High)

## Objective

Implement multi-dimensional array feature types: `Array2D`, `Array3D`, `Array4D`, `Array5D`, and `Translation` types.

## Required Reading

Before starting, read these files completely:

```
lib/dataset_manager/features.ex
lib/dataset_manager/features/value.ex
lib/dataset_manager/features/sequence.ex
lib/dataset_manager/features/image.ex
docs/20251231/gap_analysis/02_feature_types.md
```

## Context

The Python `datasets` library defines array types for multi-dimensional tensor data:
- `Array2D(shape=(M, N), dtype="float32")` - 2D arrays
- `Array3D` through `Array5D` - Higher dimensional arrays

These are critical for:
- Image data (H x W x C)
- Audio spectrograms
- Video frames
- Embeddings
- Any tensor data

Also needed is `Translation` for multilingual datasets.

## Implementation Requirements

### 1. Create Array Feature Types

Create `lib/dataset_manager/features/array.ex`:

```elixir
defmodule HfDatasetsEx.Features.Array2D do
  @moduledoc """
  A 2-dimensional array feature type.

  ## Examples

      # 28x28 grayscale image
      %Array2D{shape: {28, 28}, dtype: :float32}

      # 100x768 embedding matrix
      %Array2D{shape: {100, 768}, dtype: :float32}

  """

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
    if length(value) == rows and Enum.all?(value, &(is_list(&1) and length(&1) == cols)) do
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
    Nx.tensor(value, type: dtype_to_nx(dtype))
    |> Nx.reshape(shape)
  end

  def to_nx(%Nx.Tensor{} = tensor, %__MODULE__{shape: shape, dtype: dtype}) do
    tensor
    |> Nx.as_type(dtype_to_nx(dtype))
    |> Nx.reshape(shape)
  end

  defp dtype_to_nx(dtype) do
    HfDatasetsEx.Features.Value.dtype_to_nx(dtype)
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

  def validate(value, %__MODULE__{shape: {d1, d2, d3}}) when is_list(value) do
    # Validate nested list shape
    valid = length(value) == d1 and
            Enum.all?(value, fn v1 ->
              is_list(v1) and length(v1) == d2 and
              Enum.all?(v1, fn v2 ->
                is_list(v2) and length(v2) == d3
              end)
            end)

    if valid, do: {:ok, value}, else: {:error, :shape_mismatch}
  end

  @spec to_nx(any(), t()) :: Nx.Tensor.t()
  def to_nx(value, %__MODULE__{shape: shape, dtype: dtype}) do
    Nx.tensor(value, type: HfDatasetsEx.Features.Value.dtype_to_nx(dtype))
    |> Nx.reshape(shape)
  end
end

defmodule HfDatasetsEx.Features.Array4D do
  @moduledoc """
  A 4-dimensional array feature type.

  ## Examples

      # Video frames: frames x height x width x channels
      %Array4D{shape: {16, 224, 224, 3}, dtype: :uint8}

  """

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

  @spec to_nx(any(), t()) :: Nx.Tensor.t()
  def to_nx(value, %__MODULE__{shape: shape, dtype: dtype}) do
    Nx.tensor(value, type: HfDatasetsEx.Features.Value.dtype_to_nx(dtype))
    |> Nx.reshape(shape)
  end
end

defmodule HfDatasetsEx.Features.Array5D do
  @moduledoc """
  A 5-dimensional array feature type.

  ## Examples

      # Batched video: batch x frames x height x width x channels
      %Array5D{shape: {8, 16, 224, 224, 3}, dtype: :uint8}

  """

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

  @spec to_nx(any(), t()) :: Nx.Tensor.t()
  def to_nx(value, %__MODULE__{shape: shape, dtype: dtype}) do
    Nx.tensor(value, type: HfDatasetsEx.Features.Value.dtype_to_nx(dtype))
    |> Nx.reshape(shape)
  end
end
```

### 2. Create Translation Types

Create `lib/dataset_manager/features/translation.ex`:

```elixir
defmodule HfDatasetsEx.Features.Translation do
  @moduledoc """
  A feature for fixed-language translations.

  ## Examples

      # English-German-French translations
      translation = Translation.new(["en", "de", "fr"])

      # Data format:
      # %{"en" => "Hello", "de" => "Hallo", "fr" => "Bonjour"}

  """

  @type t :: %__MODULE__{
    languages: [String.t()]
  }

  @enforce_keys [:languages]
  defstruct [:languages]

  @spec new([String.t()]) :: t()
  def new(languages) when is_list(languages) do
    %__MODULE__{languages: Enum.sort(languages)}
  end

  @doc """
  Validate that a translation map has all required languages.
  """
  @spec validate(map(), t()) :: {:ok, map()} | {:error, term()}
  def validate(value, %__MODULE__{languages: langs}) when is_map(value) do
    value_langs = Map.keys(value) |> Enum.sort()

    if value_langs == langs do
      {:ok, value}
    else
      missing = langs -- value_langs
      extra = value_langs -- langs

      {:error, {:language_mismatch, missing: missing, extra: extra}}
    end
  end

  def validate(value, _spec), do: {:error, {:invalid_type, expected: :map, got: value}}

  @doc """
  Get text for a specific language.
  """
  @spec get(map(), String.t()) :: String.t() | nil
  def get(translation, language) when is_map(translation) do
    Map.get(translation, language)
  end
end

defmodule HfDatasetsEx.Features.TranslationVariableLanguages do
  @moduledoc """
  A feature for variable-language translations.

  Data is stored as two parallel lists: languages and translations.

  ## Examples

      # Variable language translations
      feature = TranslationVariableLanguages.new()

      # Data format:
      # %{
      #   "languages" => ["en", "de"],
      #   "translation" => ["Hello", "Hallo"]
      # }

  """

  @type t :: %__MODULE__{
    languages: [String.t()] | nil
  }

  defstruct languages: nil

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{languages: Keyword.get(opts, :languages)}
  end

  @spec validate(map(), t()) :: {:ok, map()} | {:error, term()}
  def validate(value, %__MODULE__{}) when is_map(value) do
    case value do
      %{"languages" => langs, "translation" => trans}
        when is_list(langs) and is_list(trans) ->
        if length(langs) == length(trans) do
          {:ok, value}
        else
          {:error, {:length_mismatch, languages: length(langs), translations: length(trans)}}
        end

      _ ->
        {:error, {:invalid_format, expected: ~s(%{"languages" => [...], "translation" => [...]})}}
    end
  end

  @doc """
  Convert to map format {language => translation}.
  """
  @spec to_map(map()) :: map()
  def to_map(%{"languages" => langs, "translation" => trans}) do
    Enum.zip(langs, trans) |> Map.new()
  end
end
```

### 3. Update Features Module

Add to `lib/dataset_manager/features.ex`:

```elixir
alias HfDatasetsEx.Features.{Array2D, Array3D, Array4D, Array5D, Translation, TranslationVariableLanguages}

@type feature_type ::
  Value.t() |
  ClassLabel.t() |
  Sequence.t() |
  Image.t() |
  Audio.t() |
  Array2D.t() |
  Array3D.t() |
  Array4D.t() |
  Array5D.t() |
  Translation.t() |
  TranslationVariableLanguages.t() |
  map()
```

### 4. Update Value Module

Add `dtype_to_nx/1` to `lib/dataset_manager/features/value.ex` if not present:

```elixir
@type_map %{
  int8: {:s, 8},
  int16: {:s, 16},
  int32: {:s, 32},
  int64: {:s, 64},
  uint8: {:u, 8},
  uint16: {:u, 16},
  uint32: {:u, 32},
  uint64: {:u, 64},
  float16: {:f, 16},
  float32: {:f, 32},
  float64: {:f, 64},
  bool: {:u, 8},
  bfloat16: {:bf, 16}
}

@spec dtype_to_nx(atom()) :: Nx.Type.t()
def dtype_to_nx(dtype), do: Map.get(@type_map, dtype, {:f, 32})
```

## TDD Approach

### Step 1: Write Tests First

Create `test/dataset_manager/features/array_test.exs`:

```elixir
defmodule HfDatasetsEx.Features.ArrayTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Features.{Array2D, Array3D, Array4D, Array5D}

  describe "Array2D" do
    test "new creates correct struct" do
      arr = Array2D.new({28, 28}, :float32)

      assert arr.shape == {28, 28}
      assert arr.dtype == :float32
    end

    test "validate accepts correct nested list" do
      arr = Array2D.new({2, 3}, :float32)
      value = [[1, 2, 3], [4, 5, 6]]

      assert {:ok, ^value} = Array2D.validate(value, arr)
    end

    test "validate rejects wrong shape" do
      arr = Array2D.new({2, 3}, :float32)
      value = [[1, 2], [3, 4]]  # 2x2, not 2x3

      assert {:error, {:shape_mismatch, _}} = Array2D.validate(value, arr)
    end

    test "validate accepts Nx tensor" do
      arr = Array2D.new({2, 3}, :float32)
      tensor = Nx.tensor([[1, 2, 3], [4, 5, 6]])

      assert {:ok, ^tensor} = Array2D.validate(tensor, arr)
    end

    test "to_nx converts list to tensor" do
      arr = Array2D.new({2, 3}, :float32)
      value = [[1, 2, 3], [4, 5, 6]]

      tensor = Array2D.to_nx(value, arr)

      assert Nx.shape(tensor) == {2, 3}
      assert Nx.type(tensor) == {:f, 32}
    end
  end

  describe "Array3D" do
    test "validates 3D tensor" do
      arr = Array3D.new({2, 3, 4}, :float32)
      tensor = Nx.iota({2, 3, 4})

      assert {:ok, ^tensor} = Array3D.validate(tensor, arr)
    end

    test "to_nx creates correct tensor" do
      arr = Array3D.new({2, 2, 2}, :int32)
      value = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]]

      tensor = Array3D.to_nx(value, arr)

      assert Nx.shape(tensor) == {2, 2, 2}
      assert Nx.type(tensor) == {:s, 32}
    end
  end

  describe "Array4D" do
    test "validates 4D tensor" do
      arr = Array4D.new({2, 3, 4, 5}, :float32)
      tensor = Nx.iota({2, 3, 4, 5})

      assert {:ok, ^tensor} = Array4D.validate(tensor, arr)
    end
  end

  describe "Array5D" do
    test "validates 5D tensor" do
      arr = Array5D.new({2, 3, 4, 5, 6}, :float32)
      tensor = Nx.iota({2, 3, 4, 5, 6})

      assert {:ok, ^tensor} = Array5D.validate(tensor, arr)
    end
  end
end
```

Create `test/dataset_manager/features/translation_test.exs`:

```elixir
defmodule HfDatasetsEx.Features.TranslationTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Features.{Translation, TranslationVariableLanguages}

  describe "Translation" do
    test "new creates sorted languages" do
      trans = Translation.new(["fr", "en", "de"])

      assert trans.languages == ["de", "en", "fr"]
    end

    test "validate accepts correct map" do
      trans = Translation.new(["en", "de"])
      value = %{"en" => "Hello", "de" => "Hallo"}

      assert {:ok, ^value} = Translation.validate(value, trans)
    end

    test "validate rejects missing language" do
      trans = Translation.new(["en", "de", "fr"])
      value = %{"en" => "Hello", "de" => "Hallo"}

      assert {:error, {:language_mismatch, missing: ["fr"], extra: []}} =
        Translation.validate(value, trans)
    end

    test "get retrieves translation" do
      value = %{"en" => "Hello", "de" => "Hallo"}

      assert Translation.get(value, "en") == "Hello"
      assert Translation.get(value, "de") == "Hallo"
    end
  end

  describe "TranslationVariableLanguages" do
    test "validate accepts correct format" do
      trans = TranslationVariableLanguages.new()
      value = %{
        "languages" => ["en", "de"],
        "translation" => ["Hello", "Hallo"]
      }

      assert {:ok, ^value} = TranslationVariableLanguages.validate(value, trans)
    end

    test "validate rejects mismatched lengths" do
      trans = TranslationVariableLanguages.new()
      value = %{
        "languages" => ["en", "de", "fr"],
        "translation" => ["Hello", "Hallo"]
      }

      assert {:error, {:length_mismatch, _}} =
        TranslationVariableLanguages.validate(value, trans)
    end

    test "to_map converts to language map" do
      value = %{
        "languages" => ["en", "de"],
        "translation" => ["Hello", "Hallo"]
      }

      result = TranslationVariableLanguages.to_map(value)

      assert result == %{"en" => "Hello", "de" => "Hallo"}
    end
  end
end
```

### Step 2: Run Tests (They Should Fail)

```bash
mix test test/dataset_manager/features/array_test.exs
mix test test/dataset_manager/features/translation_test.exs
```

### Step 3: Implement Until Tests Pass

### Step 4: Quality Checks

```bash
mix format
mix credo --strict
mix dialyzer
mix test
```

## Acceptance Criteria

- [ ] All tests pass
- [ ] `mix format` produces no changes
- [ ] `mix credo --strict` reports no issues
- [ ] `mix dialyzer` reports no errors
- [ ] `mix compile --warnings-as-errors` succeeds
- [ ] Array types validate shape correctly
- [ ] to_nx produces correct Nx tensors
- [ ] Translation types validate languages

## Files to Create/Modify

| File | Action |
|------|--------|
| `lib/dataset_manager/features/array.ex` | Create |
| `lib/dataset_manager/features/translation.ex` | Create |
| `lib/dataset_manager/features.ex` | Update type definitions |
| `lib/dataset_manager/features/value.ex` | Add dtype_to_nx if needed |
| `test/dataset_manager/features/array_test.exs` | Create |
| `test/dataset_manager/features/translation_test.exs` | Create |

## Dependencies

- `nx` - For tensor operations (already added in prompt 02)
