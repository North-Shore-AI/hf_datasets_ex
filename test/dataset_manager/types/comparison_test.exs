defmodule HfDatasetsEx.Types.ComparisonTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Types.{Comparison, LabeledComparison}

  describe "new/4" do
    test "creates comparison with string responses" do
      comp = Comparison.new("What is AI?", "AI is...", "I don't know")

      assert comp.prompt == "What is AI?"
      assert comp.response_a == "AI is..."
      assert comp.response_b == "I don't know"
      assert comp.metadata == %{}
    end

    test "creates comparison with metadata" do
      comp = Comparison.new("Q", "A", "B", %{source: :test})

      assert comp.metadata.source == :test
    end
  end

  describe "from_hh_rlhf/1" do
    test "parses HH-RLHF format" do
      data = %{
        "chosen" => "Human: Hi\n\nAssistant: Hello!",
        "rejected" => "Human: Hi\n\nAssistant: Go away"
      }

      {:ok, comp} = Comparison.from_hh_rlhf(data)

      assert comp.metadata.source == :hh_rlhf
      # response_a should be the chosen conversation
      assert is_struct(comp.response_a, HfDatasetsEx.Types.Conversation)
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_hh_rlhf_format} = Comparison.from_hh_rlhf(%{})
    end
  end

  describe "from_helpsteer/1" do
    test "parses HelpSteer format with label" do
      data = %{
        "prompt" => "What is ML?",
        "response_a" => "Machine Learning is...",
        "response_b" => "ML means...",
        "label" => "A"
      }

      {:ok, comp} = Comparison.from_helpsteer(data)

      assert comp.prompt == "What is ML?"
      assert comp.response_a == "Machine Learning is..."
      assert comp.metadata.label == "A"
    end

    test "parses HelpSteer2 format with score" do
      data = %{
        "prompt" => "Explain AI",
        "response" => "AI is...",
        "score" => 4.5
      }

      {:ok, comp} = Comparison.from_helpsteer(data)

      assert comp.prompt == "Explain AI"
      assert comp.metadata.score == 4.5
    end
  end

  describe "from_ultrafeedback/1" do
    test "parses UltraFeedback format" do
      data = %{
        "prompt" => "What is AI?",
        "responses" => [
          %{"model" => "gpt4", "response" => "AI is...", "score" => 5},
          %{"model" => "llama", "response" => "Dunno", "score" => 1}
        ]
      }

      {:ok, comp} = Comparison.from_ultrafeedback(data)

      assert comp.prompt == "What is AI?"
      # Best response (highest score) should be response_a
      assert comp.response_a == "AI is..."
      assert comp.response_b == "Dunno"
    end

    test "returns error for less than 2 responses" do
      data = %{"prompt" => "Q", "responses" => [%{"response" => "A"}]}

      assert {:error, :invalid_ultrafeedback_format} = Comparison.from_ultrafeedback(data)
    end
  end
end

defmodule HfDatasetsEx.Types.LabeledComparisonTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Types.LabeledComparison

  describe "new/2" do
    test "creates preference with margin" do
      pref = LabeledComparison.new(:a, 0.8)

      assert pref.preferred == :a
      assert pref.margin == 0.8
    end

    test "creates preference without margin" do
      pref = LabeledComparison.new(:b)

      assert pref.preferred == :b
      assert pref.margin == nil
    end
  end

  describe "from_label/1" do
    test "parses 'A' label" do
      {:ok, pref} = LabeledComparison.from_label("A")
      assert pref.preferred == :a
    end

    test "parses 'B' label" do
      {:ok, pref} = LabeledComparison.from_label("B")
      assert pref.preferred == :b
    end

    test "parses 'tie' label" do
      {:ok, pref} = LabeledComparison.from_label("tie")
      assert pref.preferred == :tie
    end

    test "parses 'chosen' label" do
      {:ok, pref} = LabeledComparison.from_label("chosen")
      assert pref.preferred == :a
    end

    test "returns error for invalid label" do
      assert {:error, {:invalid_label, "xyz"}} = LabeledComparison.from_label("xyz")
    end
  end

  describe "to_score/1" do
    test "returns 1.0 for :a" do
      assert LabeledComparison.to_score(LabeledComparison.new(:a)) == 1.0
    end

    test "returns 0.0 for :b" do
      assert LabeledComparison.to_score(LabeledComparison.new(:b)) == 0.0
    end

    test "returns 0.5 for :tie" do
      assert LabeledComparison.to_score(LabeledComparison.new(:tie)) == 0.5
    end
  end

  describe "preferred?/2" do
    test "checks if response is preferred" do
      pref = LabeledComparison.new(:a)

      assert LabeledComparison.preferred?(pref, :a) == true
      assert LabeledComparison.preferred?(pref, :b) == false
    end
  end
end
