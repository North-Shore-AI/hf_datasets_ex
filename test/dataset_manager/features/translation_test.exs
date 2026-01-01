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
