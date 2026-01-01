# Gap Analysis: Feature Types

## Overview

The Python `datasets` library defines 15+ feature types in `features/features.py` and related modules. The Elixir port implements 6 types. This document catalogs the missing feature types.

## Current Elixir Implementation

| Type | Module | Status |
|------|--------|--------|
| `Value` | `HfDatasetsEx.Features.Value` | ✅ Complete |
| `ClassLabel` | `HfDatasetsEx.Features.ClassLabel` | ✅ Complete |
| `Sequence` | `HfDatasetsEx.Features.Sequence` | ✅ Complete |
| `Image` | `HfDatasetsEx.Features.Image` | ✅ Basic |
| `Audio` | `HfDatasetsEx.Features.Audio` | ✅ Basic |
| `Dict/Map` | Inline maps | ✅ Native Elixir |

## Missing Feature Types

### Array Types (P1 - High Priority)

Used for multi-dimensional tensor data in ML workflows.

#### Array2D

```python
# Python
class Array2D:
    shape: tuple[int, int]
    dtype: str  # e.g., "float32"
```

```elixir
# Proposed Elixir
defmodule HfDatasetsEx.Features.Array2D do
  @type t :: %__MODULE__{
    shape: {non_neg_integer(), non_neg_integer()},
    dtype: atom()
  }

  defstruct [:shape, :dtype]

  @spec new({non_neg_integer(), non_neg_integer()}, atom()) :: t()
  def new(shape, dtype), do: %__MODULE__{shape: shape, dtype: dtype}

  @spec validate(any(), t()) :: {:ok, any()} | {:error, term()}
  def validate(value, %__MODULE__{shape: {rows, cols}, dtype: dtype}) do
    # Validate nested list or Nx tensor shape
  end

  @spec to_nx(any(), t()) :: Nx.Tensor.t()
  def to_nx(value, %__MODULE__{shape: shape, dtype: dtype}) do
    Nx.tensor(value, type: dtype_to_nx_type(dtype))
    |> Nx.reshape(shape)
  end
end
```

#### Array3D, Array4D, Array5D

Same pattern as Array2D with different shape arities:
- `Array3D`: `{dim1, dim2, dim3}` - e.g., RGB images
- `Array4D`: `{dim1, dim2, dim3, dim4}` - e.g., video frames
- `Array5D`: `{dim1, dim2, dim3, dim4, dim5}` - e.g., batched video

### LargeList (P2)

For very large lists that need special handling.

```python
# Python
class LargeList:
    feature: FeatureType  # Type of list elements
```

```elixir
# Proposed Elixir
defmodule HfDatasetsEx.Features.LargeList do
  @type t :: %__MODULE__{
    feature: HfDatasetsEx.Features.feature_type()
  }

  defstruct [:feature]

  # Uses Arrow LargeList type for 64-bit offsets
  # Required for lists with >2^31 elements
end
```

### Translation Types (P1 - NLP Critical)

#### Translation

Fixed set of language translations.

```python
# Python
class Translation:
    languages: list[str]  # e.g., ["en", "de", "fr"]

# Example data
{"en": "Hello", "de": "Hallo", "fr": "Bonjour"}
```

```elixir
# Proposed Elixir
defmodule HfDatasetsEx.Features.Translation do
  @type t :: %__MODULE__{
    languages: [String.t()]
  }

  defstruct [:languages]

  @spec new([String.t()]) :: t()
  def new(languages) when is_list(languages) do
    %__MODULE__{languages: languages}
  end

  @spec validate(map(), t()) :: {:ok, map()} | {:error, term()}
  def validate(value, %__MODULE__{languages: langs}) when is_map(value) do
    missing = langs -- Map.keys(value)
    if Enum.empty?(missing) do
      {:ok, value}
    else
      {:error, {:missing_languages, missing}}
    end
  end
end
```

#### TranslationVariableLanguages

Variable set of language translations.

```python
# Python
class TranslationVariableLanguages:
    languages: list[str] | None  # Can be None for any languages

# Example data
{"languages": ["en", "de"], "translation": ["Hello", "Hallo"]}
```

```elixir
# Proposed Elixir
defmodule HfDatasetsEx.Features.TranslationVariableLanguages do
  @type t :: %__MODULE__{
    languages: [String.t()] | nil
  }

  defstruct [:languages]

  @spec validate(map(), t()) :: {:ok, map()} | {:error, term()}
  def validate(value, %__MODULE__{}) when is_map(value) do
    case value do
      %{"languages" => langs, "translation" => trans}
        when is_list(langs) and is_list(trans) and length(langs) == length(trans) ->
        {:ok, value}
      _ ->
        {:error, :invalid_translation_format}
    end
  end
end
```

### Media Types (P2)

#### Video

```python
# Python
class Video:
    decode: bool = True
    mode: str | None = None  # e.g., "RGB"
```

```elixir
# Proposed Elixir
defmodule HfDatasetsEx.Features.Video do
  @type t :: %__MODULE__{
    decode: boolean(),
    mode: atom() | nil
  }

  defstruct decode: true, mode: nil

  # Integration with evision or ffmpeg NIF for video decoding
  @spec decode_frames(binary(), t()) :: [Nx.Tensor.t()]
  def decode_frames(video_bytes, %__MODULE__{} = opts) do
    # Use evision or external tool to decode
  end
end
```

#### Pdf

```python
# Python
class Pdf:
    decode: bool = True
```

```elixir
# Proposed Elixir
defmodule HfDatasetsEx.Features.Pdf do
  @type t :: %__MODULE__{
    decode: boolean()
  }

  defstruct decode: true

  # Integration with pdf2image or similar
  @spec to_images(binary(), t()) :: [Image.t()]
  def to_images(pdf_bytes, %__MODULE__{}) do
    # Convert PDF pages to images
  end

  @spec to_text(binary(), t()) :: String.t()
  def to_text(pdf_bytes, %__MODULE__{}) do
    # Extract text from PDF
  end
end
```

#### Nifti (Medical Imaging)

```python
# Python
class Nifti:
    decode: bool = True
```

```elixir
# Proposed Elixir
defmodule HfDatasetsEx.Features.Nifti do
  @type t :: %__MODULE__{
    decode: boolean()
  }

  defstruct decode: true

  # NIfTI neuroimaging format
  @spec to_tensor(binary(), t()) :: Nx.Tensor.t()
  def to_tensor(nifti_bytes, %__MODULE__{}) do
    # Parse NIfTI header and voxel data
  end
end
```

## Enhanced Existing Types

### Image Enhancements

Current implementation is basic. Add:

```elixir
defmodule HfDatasetsEx.Features.Image do
  # Add these fields (Python has them)
  defstruct [
    :decode,        # ✅ Have
    :mode,          # ✅ Have
    :id,            # Add: Optional ID for the image type
    :_type          # Add: Internal type marker
  ]

  # Add these functions
  @spec cast(t(), keyword()) :: {:ok, t()} | {:error, term()}
  def cast(image, new_opts)

  @spec encode(Vix.Vips.Image.t() | Nx.Tensor.t(), keyword()) :: binary()
  def encode(image_data, opts \\ [])
end
```

### Audio Enhancements

```elixir
defmodule HfDatasetsEx.Features.Audio do
  # Add these fields
  defstruct [
    :sampling_rate,  # ✅ Have as sample_rate
    :mono,           # Add: Convert to mono
    :decode          # Add: Decode flag
  ]

  # Add resampling
  @spec resample(map(), non_neg_integer()) :: map()
  def resample(audio_data, target_rate)
end
```

## Type Mapping

### Python dtype to Elixir/Nx

| Python dtype | Elixir atom | Nx type |
|-------------|-------------|---------|
| `"int8"` | `:int8` | `{:s, 8}` |
| `"int16"` | `:int16` | `{:s, 16}` |
| `"int32"` | `:int32` | `{:s, 32}` |
| `"int64"` | `:int64` | `{:s, 64}` |
| `"uint8"` | `:uint8` | `{:u, 8}` |
| `"uint16"` | `:uint16` | `{:u, 16}` |
| `"uint32"` | `:uint32` | `{:u, 32}` |
| `"uint64"` | `:uint64` | `{:u, 64}` |
| `"float16"` | `:float16` | `{:f, 16}` |
| `"float32"` | `:float32` | `{:f, 32}` |
| `"float64"` | `:float64` | `{:f, 64}` |
| `"bool"` | `:bool` | `{:u, 8}` |
| `"string"` | `:string` | N/A |
| `"binary"` | `:binary` | N/A |

## Files to Create

| File | Purpose |
|------|---------|
| `lib/dataset_manager/features/array.ex` | Array2D-5D types |
| `lib/dataset_manager/features/translation.ex` | Translation types |
| `lib/dataset_manager/features/video.ex` | Video type |
| `lib/dataset_manager/features/pdf.ex` | PDF type |
| `lib/dataset_manager/features/nifti.ex` | NIfTI type |
| `lib/dataset_manager/features/large_list.ex` | LargeList type |

## Testing Requirements

Each feature type needs:
1. Struct creation tests
2. Validation tests (valid and invalid data)
3. Type casting tests
4. Nx tensor conversion tests (where applicable)
5. Round-trip serialization tests

## Dependencies

| Feature | Dependency | Purpose |
|---------|------------|---------|
| Video | `evision` or FFmpeg NIF | Video decoding |
| PDF | `pdf2image` or Poppler NIF | PDF rendering |
| NIfTI | Custom NIF or pure Elixir parser | Medical imaging |
| Array* | `nx` | Tensor operations |
