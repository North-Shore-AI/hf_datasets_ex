defmodule HfDatasetsEx.Media.Image do
  @moduledoc """
  Image decoding utilities using Vix/libvips.
  """

  @type mode :: String.t() | nil

  @doc """
  Decode image bytes into a Vix image.
  """
  @spec decode(binary(), keyword()) :: {:ok, Vix.Vips.Image.t()} | {:error, term()}
  def decode(bytes, opts \\ []) when is_binary(bytes) do
    mode = Keyword.get(opts, :mode)

    with {:ok, image} <- Vix.Vips.Image.new_from_buffer(bytes),
         {:ok, image} <- maybe_convert_mode(image, mode) do
      {:ok, image}
    end
  end

  @doc """
  Decode an image from a file path.
  """
  @spec decode_file(String.t(), keyword()) :: {:ok, Vix.Vips.Image.t()} | {:error, term()}
  def decode_file(path, opts \\ []) when is_binary(path) do
    case File.read(path) do
      {:ok, bytes} -> decode(bytes, opts)
      {:error, reason} -> {:error, {:file_read_error, reason}}
    end
  end

  defp maybe_convert_mode(image, nil), do: {:ok, image}

  defp maybe_convert_mode(image, "RGB") do
    Vix.Vips.Operation.colourspace(image, :VIPS_INTERPRETATION_RGB)
  end

  defp maybe_convert_mode(image, "RGBA") do
    Vix.Vips.Operation.colourspace(image, :VIPS_INTERPRETATION_RGB)
  end

  defp maybe_convert_mode(image, "L") do
    Vix.Vips.Operation.colourspace(image, :VIPS_INTERPRETATION_B_W)
  end

  defp maybe_convert_mode(image, _mode), do: {:ok, image}
end
