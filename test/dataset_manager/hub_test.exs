defmodule HfDatasetsEx.HubTest do
  use ExUnit.Case, async: false

  alias HfDatasetsEx.{Dataset, Hub}

  @hub_token System.get_env("HF_TOKEN") || System.get_env("HF_HUB_TOKEN")

  describe "push_to_hub/3 validation" do
    test "returns error without token" do
      dataset = Dataset.from_list([%{"x" => 1}])

      original_hf_token = System.get_env("HF_TOKEN")
      original_hf_hub_token = System.get_env("HF_HUB_TOKEN")

      System.put_env("HF_TOKEN", "")
      System.put_env("HF_HUB_TOKEN", "")

      on_exit(fn ->
        restore_env("HF_TOKEN", original_hf_token)
        restore_env("HF_HUB_TOKEN", original_hf_hub_token)
      end)

      assert {:error, :no_token} = Hub.push_to_hub(dataset, "test/repo")
    end
  end

  describe "shard creation" do
    test "creates appropriate number of shards" do
      items = Enum.map(1..100, &%{"x" => &1, "text" => String.duplicate("a", 1000)})
      dataset = Dataset.from_list(items)

      {:ok, shards} = Hub.create_shards(dataset, 10_000)

      assert length(shards) > 1
    end

    test "handles empty dataset" do
      dataset = Dataset.from_list([])

      {:ok, shards} = Hub.create_shards(dataset, 500_000)

      assert shards == []
    end
  end

  describe "dataset card generation" do
    test "generates valid card" do
      dataset =
        Dataset.from_list([
          %{"text" => "hello", "label" => 1},
          %{"text" => "world", "label" => 0}
        ])

      card = Hub.generate_dataset_card(dataset, "default", "train")

      assert card =~ "num_examples: 2"
      assert card =~ "label, text"
    end
  end

  @moduletag :hub_integration

  describe "integration" do
    @tag :skip
    test "push and delete round-trip" do
      token = @hub_token || flunk("HF token not set")

      dataset = Dataset.from_list([%{"text" => "test", "id" => 1}])

      repo_id = "hf-datasets-ex-test/integration-#{:rand.uniform(10000)}"

      assert {:ok, url} = Hub.push_to_hub(dataset, repo_id, token: token)
      assert url =~ repo_id

      assert :ok = Hub.delete_from_hub(repo_id, "default", token: token)
    end
  end

  defp restore_env(_key, nil), do: :ok
  defp restore_env(key, value), do: System.put_env(key, value)
end
