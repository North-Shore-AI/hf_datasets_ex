defmodule HfDatasetsEx.RegistryTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Registry

  test "lists available datasets" do
    assert Enum.sort(Registry.list_available()) == [
             :arena_140k,
             :caltech101,
             :deepcoder,
             :deepmath,
             :deepmath_reasoning,
             :feedback_collection,
             :gsm8k,
             :helpsteer2,
             :helpsteer3,
             :hendrycks_math,
             :hh_rlhf,
             :humaneval,
             :math_500,
             :mmlu,
             :mmlu_stem,
             :no_robots,
             :open_thoughts3,
             :oxford_flowers102,
             :oxford_iiit_pet,
             :polaris,
             :stanford_cars,
             :tulu3_preference,
             :tulu3_sft,
             :ultrafeedback
           ]
  end

  test "gets metadata for known dataset" do
    metadata = Registry.get_metadata(:mmlu)

    assert metadata.name == :mmlu
    assert metadata.domain == "general_knowledge"
    assert metadata.task_type == "multiple_choice_qa"
  end

  test "returns nil for unknown metadata" do
    assert Registry.get_metadata(:unknown) == nil
  end

  describe "filters" do
    test "list_by_domain/1" do
      assert Registry.list_by_domain("math") == [
               :deepmath,
               :gsm8k,
               :hendrycks_math,
               :math_500,
               :polaris
             ]

      assert Registry.list_by_domain("code") == [:deepcoder, :humaneval]
    end

    test "list_by_task_type/1" do
      assert Registry.list_by_task_type("multiple_choice_qa") == [:mmlu, :mmlu_stem]
      assert Registry.list_by_task_type("code_generation") == [:deepcoder, :humaneval]
    end

    test "list_by_difficulty/1" do
      assert Registry.list_by_difficulty("challenging") == [
               :hendrycks_math,
               :math_500,
               :mmlu,
               :mmlu_stem
             ]

      assert Registry.list_by_difficulty("medium") == [
               :caltech101,
               :deepmath,
               :gsm8k,
               :humaneval,
               :oxford_flowers102,
               :oxford_iiit_pet,
               :polaris,
               :stanford_cars
             ]
    end

    test "list_by_tag/1" do
      assert Registry.list_by_tag("reasoning") == [
               :deepmath,
               :deepmath_reasoning,
               :gsm8k,
               :hendrycks_math,
               :math_500,
               :mmlu,
               :mmlu_stem,
               :open_thoughts3,
               :polaris
             ]

      assert Registry.list_by_tag("code") == [:deepcoder, :humaneval]
    end
  end

  test "search is case-insensitive" do
    assert Registry.search("MATH") == [
             :deepmath,
             :deepmath_reasoning,
             :gsm8k,
             :hendrycks_math,
             :math_500,
             :mmlu_stem,
             :polaris
           ]

    assert Registry.search("nonexistent") == []
  end

  test "stats includes aggregate counts" do
    stats = Registry.stats()

    assert stats.total_datasets == 24

    assert Enum.sort(stats.domains) == [
             "chat",
             "code",
             "general_knowledge",
             "math",
             "preference",
             "reasoning",
             "rubric_evaluation",
             "stem",
             "vision"
           ]

    assert stats.by_domain["math"] == 5
    assert stats.by_task_type["multiple_choice_qa"] == 2
  end

  test "summary renders readable output" do
    summary = Registry.summary()

    assert summary =~ "Total Datasets: 24"
    assert summary =~ "general_knowledge"
    assert summary =~ "code"
  end
end
