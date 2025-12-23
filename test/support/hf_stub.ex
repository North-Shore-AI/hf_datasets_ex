defmodule TestSupport.HfStub do
  @moduledoc false

  import Plug.Conn

  def start(fixtures \\ default_fixtures()) do
    bypass = Bypass.open()
    endpoint = "http://localhost:#{bypass.port}"
    cache_dir = shared_cache_dir()

    apply_env(%{endpoint: endpoint, cache_dir: cache_dir})

    path_map = build_path_map(fixtures)

    path_map
    |> Map.keys()
    |> Enum.each(fn path ->
      Enum.each(["GET", "HEAD"], fn method ->
        Bypass.stub(bypass, method, path, fn conn -> handle_request(conn, path_map) end)
      end)
    end)

    {:ok, %{bypass: bypass, cache_dir: cache_dir, endpoint: endpoint}}
  end

  def stop(%{bypass: bypass, cache_dir: cache_dir}) do
    Bypass.down(bypass)
    clear_env()
    _ = cache_dir
    :ok
  end

  def stop(stub) when is_list(stub) do
    stop(Map.new(stub))
  end

  def apply_env(%{endpoint: endpoint, cache_dir: cache_dir}) do
    Application.put_env(:hf_hub, :endpoint, endpoint)
    Application.put_env(:hf_hub, :cache_dir, cache_dir)
    :ok
  end

  def clear_env do
    Application.delete_env(:hf_hub, :endpoint)
    Application.delete_env(:hf_hub, :cache_dir)
    :ok
  end

  defp handle_request(conn, path_map) do
    case Map.get(path_map, conn.request_path) do
      {:json, body} ->
        json(conn, 200, body)

      {:raw, body, content_type} ->
        conn
        |> put_resp_content_type(content_type)
        |> send_resp(200, body)

      nil ->
        send_resp(conn, 404, "not found")
    end
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp build_path_map(fixtures) do
    Enum.reduce(fixtures, %{}, fn {repo_id, fixture}, acc ->
      config = Map.get(fixture, :config, "main")
      configs = Map.get(fixture, :configs, [config])
      splits = Map.get(fixture, :splits, %{})
      files = Map.fetch!(fixture, :files)

      configs_body = %{
        "cardData" => %{"configs" => Enum.map(configs, &%{"config_name" => &1})}
      }

      infos_body =
        Enum.reduce(configs, %{}, fn config_name, infos_acc ->
          split_map = Map.new(splits, fn {split, _paths} -> {split, %{}} end)
          Map.put(infos_acc, config_name, %{"splits" => split_map})
        end)

      tree_body =
        Enum.map(files, fn {path, content} ->
          %{
            "type" => "file",
            "path" => path,
            "size" => byte_size(content)
          }
        end)

      acc
      |> Map.put("/api/datasets/#{repo_id}", {:json, configs_body})
      |> Map.put("/api/datasets/#{repo_id}/tree/main", {:json, tree_body})
      |> Map.put("/datasets/#{repo_id}/resolve/main/dataset_infos.json", {:json, infos_body})
      |> Map.merge(file_paths(repo_id, files))
    end)
  end

  defp file_paths(repo_id, files) do
    Enum.reduce(files, %{}, fn {path, content}, acc ->
      Map.put(
        acc,
        "/datasets/#{repo_id}/resolve/main/#{path}",
        {:raw, content, content_type(path)}
      )
    end)
  end

  defp content_type(path) do
    case Path.extname(path) do
      ".jsonl" -> "application/jsonl"
      ".json" -> "application/json"
      ".parquet" -> "application/octet-stream"
      _ -> "application/octet-stream"
    end
  end

  defp default_fixtures do
    cached(:default_fixtures, fn ->
      %{
        "openai/gsm8k" => %{
          config: "main",
          splits: %{
            "train" => ["data/train.jsonl"],
            "test" => ["data/test.jsonl"]
          },
          files: %{
            "data/train.jsonl" =>
              ~s|{"question":"What is 2+2?","answer":"#### 4"}\n{"question":"What is 10-3?","answer":"#### 7"}\n|,
            "data/test.jsonl" => ~s|{"question":"What is 1+1?","answer":"#### 2"}\n|
          }
        },
        "allenai/tulu-3-sft-mixture" => %{
          config: "main",
          splits: %{"train" => ["data/train.jsonl"]},
          files: %{
            "data/train.jsonl" =>
              ~s|{"messages":[{"role":"user","content":"Hello?"},{"role":"assistant","content":"Hi!"}],"source":"test"}\n|
          }
        },
        "HuggingFaceH4/no_robots" => %{
          config: "main",
          splits: %{"train" => ["data/train.jsonl"]},
          files: %{
            "data/train.jsonl" =>
              ~s|{"messages":[{"role":"user","content":"Explain gravity."},{"role":"assistant","content":"Gravity pulls objects together."}],"source":"test"}\n|
          }
        },
        "Anthropic/hh-rlhf" => %{
          config: "main",
          splits: %{"train" => ["data/train.jsonl"]},
          files: %{
            "data/train.jsonl" =>
              ~s|{"chosen":"Human: Hi\\n\\nAssistant: Hello!","rejected":"Human: Hi\\n\\nAssistant: Go away."}\n|
          }
        },
        "nvidia/HelpSteer3" => %{
          config: "preference",
          configs: ["preference"],
          splits: %{"train" => ["preference/train.jsonl"]},
          files: %{
            "preference/train.jsonl" =>
              ~s|{"context":[{"role":"user","content":"What is ML?"}],"response1":"Machine learning is...","response2":"ML is...","overall_preference":-1}\n|
          }
        },
        "argilla/ultrafeedback-binarized-preferences" => %{
          config: "main",
          splits: %{"train" => ["data/train.jsonl"]},
          files: %{
            "data/train.jsonl" =>
              ~s|{"instruction":"Explain ML","chosen_response":"Machine learning is...","rejected_response":"ML is magic."}\n|
          }
        },
        "open-thoughts/OpenThoughts3-1.2M" => %{
          config: "main",
          splits: %{"train" => ["data/train.jsonl"]},
          files: %{
            "data/train.jsonl" =>
              ~s|{"conversations":[{"from":"human","value":"What is 2+2?"},{"from":"gpt","value":"<think>2+2=4</think> 4"}]}\n|
          }
        },
        "zwhe99/DeepMath-103K" => %{
          config: "main",
          splits: %{"train" => ["data/train.jsonl"]},
          files: %{
            "data/train.jsonl" => ~s|{"problem":"Solve 2x=6","solution":"x=3"}\n|
          }
        },
        "HuggingFaceH4/MATH-500" => %{
          config: "main",
          splits: %{"test" => ["data/test.jsonl"]},
          files: %{
            "data/test.jsonl" =>
              ~s|{"problem":"Solve for x: 2x+2=6","solution":"\\boxed{2}","level":"Level 1","type":"algebra"}\n|
          }
        },
        "EleutherAI/hendrycks_math" => %{
          config: "main",
          splits: %{"train" => ["data/train.jsonl"]},
          files: %{
            "data/train.jsonl" =>
              ~s|{"problem":"What is 3+4?","solution":"\\boxed{7}","level":"Level 1","type":"algebra"}\n|
          }
        },
        "prometheus-eval/Feedback-Collection" => %{
          config: "main",
          splits: %{"train" => ["new_feedback_collection.json"]},
          files: %{
            "new_feedback_collection.json" =>
              Jason.encode!([
                %{
                  "instruction" => "Explain photosynthesis.",
                  "criteria" => "Accuracy and clarity.",
                  "reference_answer" => "Plants convert sunlight into energy.",
                  "score1_description" => "Poor",
                  "score2_description" => "Fair",
                  "score3_description" => "Good",
                  "score4_description" => "Very good",
                  "score5_description" => "Excellent"
                }
              ])
          }
        },
        "openai/openai_humaneval" => %{
          config: "main",
          splits: %{"test" => ["openai_humaneval/test-00000-of-00001.parquet"]},
          files: %{
            "openai_humaneval/test-00000-of-00001.parquet" => humaneval_parquet()
          }
        },
        "cais/mmlu" => %{
          config: "all",
          configs: ["all"],
          splits: %{
            "train" => ["all/train-00000-of-00001.parquet"],
            "validation" => ["all/validation-00000-of-00001.parquet"],
            "test" => ["all/test-00000-of-00001.parquet"]
          },
          files: %{
            "all/train-00000-of-00001.parquet" => mmlu_parquet(),
            "all/validation-00000-of-00001.parquet" => mmlu_parquet(),
            "all/test-00000-of-00001.parquet" => mmlu_parquet()
          }
        },
        "dpdl-benchmark/caltech101" => %{
          config: "main",
          splits: %{"train" => ["data/train.jsonl"]},
          files: %{
            "data/train.jsonl" =>
              ~s|{"image":{"bytes":"AAECAw=="},"label":0}\n{"image":{"bytes":"AQIDBA=="},"label":1}\n|
          }
        }
      }
    end)
  end

  defp mmlu_parquet do
    cached(:mmlu_parquet, fn ->
      rows = [
        %{
          "subject" => "abstract_algebra",
          "question" => "What is 2+2?",
          "choices" => ["A", "B", "C", "D"],
          "answer" => "A"
        },
        %{
          "subject" => "abstract_algebra",
          "question" => "What is 3+1?",
          "choices" => ["A", "B", "C", "D"],
          "answer" => "B"
        }
      ]

      rows
      |> Explorer.DataFrame.new()
      |> Explorer.DataFrame.dump_parquet!()
    end)
  end

  defp humaneval_parquet do
    cached(:humaneval_parquet, fn ->
      rows = [
        %{
          "task_id" => "HumanEval/0",
          "prompt" => "def add(a, b):\n    \"\"\"Add two numbers\"\"\"\n",
          "canonical_solution" => "    return a + b\n",
          "test" => "def check(candidate):\n    assert candidate(1, 2) == 3\n",
          "entry_point" => "add"
        }
      ]

      rows
      |> Explorer.DataFrame.new()
      |> Explorer.DataFrame.dump_parquet!()
    end)
  end

  defp cached(key, fun) do
    cache_key = {__MODULE__, key}

    case :persistent_term.get(cache_key, :missing) do
      :missing ->
        value = fun.()
        :persistent_term.put(cache_key, value)
        value

      value ->
        value
    end
  end

  defp shared_cache_dir do
    cached(:cache_dir, fn ->
      cache_dir = Path.join(System.tmp_dir!(), "hf_hub_cache_test")
      File.mkdir_p!(cache_dir)
      cache_dir
    end)
  end

  def cleanup_cache do
    cache_key = {__MODULE__, :cache_dir}

    case :persistent_term.get(cache_key, :missing) do
      :missing ->
        :ok

      cache_dir ->
        File.rm_rf!(cache_dir)
        :persistent_term.erase(cache_key)
        :ok
    end
  end
end
