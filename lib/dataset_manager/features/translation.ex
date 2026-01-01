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
