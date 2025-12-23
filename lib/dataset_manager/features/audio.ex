defmodule HfDatasetsEx.Features.Audio do
  @moduledoc """
  Audio feature type.

  Represents audio data with sample rate and format information.

  ## Example

      # Basic audio feature
      Audio.new()

      # Audio with specific sample rate
      Audio.new(sampling_rate: 16000)

  """

  @type t :: %__MODULE__{
          sampling_rate: non_neg_integer() | nil,
          mono: boolean(),
          decode: boolean()
        }

  defstruct sampling_rate: nil, mono: true, decode: true

  @doc """
  Create a new Audio type.

  ## Options

    * `:sampling_rate` - Audio sample rate in Hz (e.g., 16000, 44100)
    * `:mono` - Whether to convert to mono (default: true)
    * `:decode` - Whether to decode audio when loading (default: true)

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      sampling_rate: Keyword.get(opts, :sampling_rate),
      mono: Keyword.get(opts, :mono, true),
      decode: Keyword.get(opts, :decode, true)
    }
  end

  @doc "Create a 16kHz audio feature (common for speech)"
  @spec speech() :: t()
  def speech, do: new(sampling_rate: 16000)

  @doc "Create a 44.1kHz audio feature (CD quality)"
  @spec cd_quality() :: t()
  def cd_quality, do: new(sampling_rate: 44100)
end
