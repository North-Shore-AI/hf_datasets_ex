defmodule HfDatasetsEx.LoadDatasetTest do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias HfDatasetsEx.{Dataset, DatasetDict, IterableDataset}

  setup do
    bypass = Bypass.open()
    repo_id = "org/test-ds"
    endpoint = "http://localhost:#{bypass.port}"
    cache_dir = Path.join(System.tmp_dir!(), "hf_hub_cache_#{System.unique_integer([:positive])}")

    Application.put_env(:hf_hub, :endpoint, endpoint)
    Application.put_env(:hf_hub, :cache_dir, cache_dir)
    File.mkdir_p!(cache_dir)

    tree = [
      %{"type" => "file", "path" => "data/train.jsonl", "size" => 10},
      %{"type" => "file", "path" => "data/test.jsonl", "size" => 10}
    ]

    configs = %{"cardData" => %{"configs" => [%{"config_name" => "main"}]}}
    infos = %{"main" => %{"splits" => %{"train" => %{}, "test" => %{}}}}

    train_content = ~s|{"id": 1, "text": "alpha"}\n{"id": 2, "text": "beta"}\n|
    test_content = ~s|{"id": 3, "text": "gamma"}\n|

    datasets_path = "/api/datasets/#{repo_id}"
    infos_path = "/datasets/#{repo_id}/resolve/main/dataset_infos.json"
    tree_path = "/api/datasets/#{repo_id}/tree/main"
    train_path = "/datasets/#{repo_id}/resolve/main/data/train.jsonl"
    test_path = "/datasets/#{repo_id}/resolve/main/data/test.jsonl"

    Bypass.expect(bypass, fn conn ->
      case conn.request_path do
        ^datasets_path ->
          json(conn, 200, configs)

        ^infos_path ->
          json(conn, 200, infos)

        ^tree_path ->
          json(conn, 200, tree)

        ^train_path ->
          conn
          |> put_resp_content_type("application/jsonl")
          |> send_resp(200, train_content)

        ^test_path ->
          conn
          |> put_resp_content_type("application/jsonl")
          |> send_resp(200, test_content)

        _ ->
          send_resp(conn, 404, "not found")
      end
    end)

    on_exit(fn ->
      Application.delete_env(:hf_hub, :endpoint)
      Application.delete_env(:hf_hub, :cache_dir)
      File.rm_rf!(cache_dir)
    end)

    {:ok, repo_id: repo_id}
  end

  test "load_dataset returns DatasetDict when split is nil", %{repo_id: repo_id} do
    {:ok, dataset_dict} = HfDatasetsEx.load_dataset(repo_id)

    assert %DatasetDict{} = dataset_dict
    assert Enum.sort(DatasetDict.split_names(dataset_dict)) == ["test", "train"]
    assert length(dataset_dict["train"].items) == 2
    assert length(dataset_dict["test"].items) == 1
  end

  test "load_dataset returns Dataset when split is specified", %{repo_id: repo_id} do
    {:ok, dataset} = HfDatasetsEx.load_dataset(repo_id, split: "train")

    assert %Dataset{} = dataset
    assert Enum.map(dataset.items, & &1["id"]) == [1, 2]
  end

  test "load_dataset streaming returns IterableDataset", %{repo_id: repo_id} do
    {:ok, iterable} = HfDatasetsEx.load_dataset(repo_id, split: "train", streaming: true)

    assert %IterableDataset{} = iterable
    items = IterableDataset.take(iterable, 2)
    assert Enum.map(items, & &1["id"]) == [1, 2]
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
