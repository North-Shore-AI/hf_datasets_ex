defmodule HfDatasetsEx.Loader.GSM8KTest do
  use TestSupport.HfCase

  alias HfDatasetsEx.Loader.GSM8K

  describe "extract_numerical_answer/1" do
    test "extracts integer answer from GSM8K format" do
      assert GSM8K.extract_numerical_answer("The answer is #### 42") == 42.0
    end

    test "extracts answer with commas" do
      assert GSM8K.extract_numerical_answer("#### 1,234") == 1234.0
    end

    test "extracts decimal answer" do
      assert GSM8K.extract_numerical_answer("#### 1234.56") == 1234.56
    end

    test "extracts answer with dollar sign" do
      assert GSM8K.extract_numerical_answer("#### $50") == 50.0
    end

    test "returns nil for no answer marker" do
      assert GSM8K.extract_numerical_answer("no answer here") == nil
    end

    test "returns nil for nil input" do
      assert GSM8K.extract_numerical_answer(nil) == nil
    end

    test "extracts answer from multi-step reasoning" do
      answer = """
      Step 1: Calculate first value
      <<5+3=8>>
      Step 2: Multiply by 2
      <<8*2=16>>
      #### 16
      """

      assert GSM8K.extract_numerical_answer(answer) == 16.0
    end
  end

  describe "load/1" do
    test "loads GSM8K data" do
      {:ok, dataset} = GSM8K.load(TestHelper.data_opts())

      assert dataset.name == "gsm8k"
      assert length(dataset.items) > 0
    end

    test "respects sample_size option" do
      {:ok, dataset} = GSM8K.load(TestHelper.data_opts(sample_size: 1))

      assert length(dataset.items) == 1
    end

    test "items have correct structure" do
      {:ok, dataset} = GSM8K.load(TestHelper.data_opts(sample_size: 1))

      first = hd(dataset.items)
      assert is_binary(first.id)
      assert is_map(first.expected)
      assert Map.has_key?(first.expected, :answer)
      assert is_map(first.metadata)
    end
  end

  describe "load/1 with real data" do
    @describetag :live
    @tag timeout: 120_000

    test "loads real GSM8K train data from HuggingFace" do
      {:ok, dataset} = GSM8K.load(split: :train)

      assert dataset.name == "gsm8k"
      # GSM8K has ~7.5K train examples
      assert length(dataset.items) > 7000
      assert dataset.metadata.source =~ "huggingface"
      assert dataset.metadata.split == "train"
    end

    @tag timeout: 120_000
    test "loads real GSM8K test data from HuggingFace" do
      {:ok, dataset} = GSM8K.load(split: :test)

      assert dataset.name == "gsm8k"
      # GSM8K has ~1.3K test examples
      assert length(dataset.items) > 1000
      assert dataset.metadata.split == "test"
    end

    @tag timeout: 120_000
    test "items have correct structure from HuggingFace" do
      {:ok, dataset} = GSM8K.load(split: :test, sample_size: 10)

      first = hd(dataset.items)
      assert is_binary(first.id)
      assert is_map(first.input)
      assert Map.has_key?(first.input, :question)
      assert is_binary(first.input.question)
      # Expected should be a map with :answer and :reasoning keys
      assert is_map(first.expected)
      assert Map.has_key?(first.expected, :answer)
      assert Map.has_key?(first.expected, :reasoning)
      assert is_number(first.expected.answer) or is_nil(first.expected.answer)
      assert is_map(first.metadata)
    end

    @tag timeout: 120_000
    test "sample_size limits items from HuggingFace" do
      {:ok, dataset} = GSM8K.load(split: :test, sample_size: 50)

      assert length(dataset.items) == 50
    end
  end
end
