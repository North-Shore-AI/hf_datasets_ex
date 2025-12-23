defmodule HfDatasetsEx.DataFilesTest do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias HfDatasetsEx.DataFiles

  setup do
    bypass = Bypass.open()
    repo_id = "org/test-ds"
    endpoint = "http://localhost:#{bypass.port}"
    cache_dir = Path.join(System.tmp_dir!(), "hf_hub_cache_#{System.unique_integer([:positive])}")

    Application.put_env(:hf_hub, :endpoint, endpoint)
    Application.put_env(:hf_hub, :cache_dir, cache_dir)
    File.mkdir_p!(cache_dir)

    on_exit(fn ->
      Application.delete_env(:hf_hub, :endpoint)
      Application.delete_env(:hf_hub, :cache_dir)
      File.rm_rf!(cache_dir)
    end)

    {:ok, bypass: bypass, repo_id: repo_id}
  end

  test "resolve/2 infers default config and maps splits", %{bypass: bypass, repo_id: repo_id} do
    tree = [
      %{"type" => "file", "path" => "README.md", "size" => 10},
      %{"type" => "file", "path" => "main/train-00000-of-00001.parquet", "size" => 10},
      %{"type" => "file", "path" => "main/test-00000-of-00001.parquet", "size" => 10},
      %{"type" => "file", "path" => "alt/train-00000-of-00001.parquet", "size" => 10}
    ]

    configs = %{
      "cardData" => %{
        "configs" => [
          %{"config_name" => "main"},
          %{"config_name" => "alt"}
        ]
      }
    }

    infos = %{
      "main" => %{"splits" => %{"train" => %{}, "test" => %{}}},
      "alt" => %{"splits" => %{"train" => %{}}}
    }

    datasets_path = "/api/datasets/#{repo_id}"
    infos_path = "/datasets/#{repo_id}/resolve/main/dataset_infos.json"
    tree_path = "/api/datasets/#{repo_id}/tree/main"

    Bypass.expect(bypass, fn conn ->
      case conn.request_path do
        ^datasets_path ->
          json(conn, 200, configs)

        ^infos_path ->
          json(conn, 200, infos)

        ^tree_path ->
          json(conn, 200, tree)

        _ ->
          send_resp(conn, 404, "not found")
      end
    end)

    {:ok, result} = DataFiles.resolve(repo_id)

    assert result.config == "main"
    assert Enum.sort(Map.keys(result.splits)) == ["test", "train"]

    train_paths = Enum.map(result.splits["train"], & &1.path)
    assert train_paths == ["main/train-00000-of-00001.parquet"]
  end

  test "resolve/2 honors explicit config", %{bypass: bypass, repo_id: repo_id} do
    tree = [
      %{"type" => "file", "path" => "main/train-00000-of-00001.parquet", "size" => 10},
      %{"type" => "file", "path" => "alt/train-00000-of-00001.parquet", "size" => 10}
    ]

    configs = %{
      "cardData" => %{
        "configs" => [
          %{"config_name" => "main"},
          %{"config_name" => "alt"}
        ]
      }
    }

    infos = %{
      "main" => %{"splits" => %{"train" => %{}}},
      "alt" => %{"splits" => %{"train" => %{}}}
    }

    datasets_path = "/api/datasets/#{repo_id}"
    infos_path = "/datasets/#{repo_id}/resolve/main/dataset_infos.json"
    tree_path = "/api/datasets/#{repo_id}/tree/main"

    Bypass.expect(bypass, fn conn ->
      case conn.request_path do
        ^datasets_path ->
          json(conn, 200, configs)

        ^infos_path ->
          json(conn, 200, infos)

        ^tree_path ->
          json(conn, 200, tree)

        _ ->
          send_resp(conn, 404, "not found")
      end
    end)

    {:ok, result} = DataFiles.resolve(repo_id, config: "alt")

    assert result.config == "alt"
    assert Enum.sort(Map.keys(result.splits)) == ["train"]

    train_paths = Enum.map(result.splits["train"], & &1.path)
    assert train_paths == ["alt/train-00000-of-00001.parquet"]
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
