defmodule HfDatasetsEx.DelegatesTest do
  use ExUnit.Case

  test "delegates to registry" do
    assert Enum.sort(HfDatasetsEx.list_available()) == [
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

    metadata = HfDatasetsEx.get_metadata(:mmlu)
    assert metadata.name == :mmlu
  end
end
