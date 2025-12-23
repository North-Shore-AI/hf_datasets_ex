defmodule HfDatasetsEx.Features.Image do
  @moduledoc """
  Image feature type.

  Represents image data, which can be stored as file paths, bytes, or URLs.

  ## Example

      # Basic image feature
      Image.new()

      # Image with specific mode and decode setting
      Image.new(mode: "RGB", decode: true)

  """

  @type mode :: String.t()

  @type t :: %__MODULE__{
          mode: mode() | nil,
          decode: boolean()
        }

  defstruct mode: nil, decode: true

  @doc """
  Create a new Image type.

  ## Options

    * `:mode` - Image mode (e.g., "RGB", "L", "RGBA")
    * `:decode` - Whether to decode images when loading (default: true)

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      mode: Keyword.get(opts, :mode),
      decode: Keyword.get(opts, :decode, true)
    }
  end

  @doc "Create an RGB image feature"
  @spec rgb() :: t()
  def rgb, do: new(mode: "RGB")

  @doc "Create a grayscale image feature"
  @spec grayscale() :: t()
  def grayscale, do: new(mode: "L")

  @doc "Create an RGBA image feature"
  @spec rgba() :: t()
  def rgba, do: new(mode: "RGBA")
end
