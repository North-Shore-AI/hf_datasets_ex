# Implementation Prompt: Hub Push Operations

## Priority: P2 (Medium)

## Objective

Implement `push_to_hub/2` and `delete_from_hub/2` for uploading and managing datasets on HuggingFace Hub.

## Required Reading

Before starting, read these files completely:

```
lib/dataset_manager/loader.ex
lib/dataset_manager/fetcher/huggingface.ex
lib/dataset_manager/data_files.ex
mix.exs (check hf_hub dependency)
docs/20251231/gap_analysis/04_hub_integration.md
```

Also check the hf_hub library documentation:
```
deps/hf_hub/lib/hf_hub/api.ex
deps/hf_hub/lib/hf_hub/download.ex
```

## Context

The Python `datasets` library provides:
- `dataset.push_to_hub(repo_id)` - Upload dataset to Hub
- `delete_from_hub(repo_id, config_name)` - Delete dataset config from Hub

The Elixir port can download datasets but cannot upload. The `hf_hub` dependency provides some Hub API access.

## Implementation Requirements

### 1. Check hf_hub Capabilities

First, verify what `hf_hub` v0.1.1 supports. If upload functions don't exist, you may need to implement direct HTTP calls.

### 2. Create Hub Module

Create `lib/dataset_manager/hub.ex`:

```elixir
defmodule HfDatasetsEx.Hub do
  @moduledoc """
  HuggingFace Hub operations for datasets.
  """

  alias HfDatasetsEx.{Dataset, DatasetDict, Export}

  @type push_opts :: [
    config_name: String.t(),
    split: String.t() | nil,
    private: boolean(),
    token: String.t() | nil,
    revision: String.t(),
    max_shard_size: non_neg_integer(),
    commit_message: String.t() | nil
  ]

  @default_max_shard_size 500 * 1024 * 1024  # 500 MB

  @doc """
  Push a dataset to HuggingFace Hub.

  ## Options

    * `:config_name` - Dataset config name (default: "default")
    * `:split` - Split name (default: "train")
    * `:private` - Create private repo (default: false)
    * `:token` - HuggingFace token (default: from env)
    * `:revision` - Branch/revision (default: "main")
    * `:max_shard_size` - Max bytes per shard (default: 500MB)
    * `:commit_message` - Git commit message

  ## Examples

      {:ok, url} = Hub.push_to_hub(dataset, "username/my-dataset")
      {:ok, url} = Hub.push_to_hub(dataset, "username/my-dataset", private: true)

  """
  @spec push_to_hub(Dataset.t(), String.t(), push_opts()) ::
    {:ok, String.t()} | {:error, term()}
  def push_to_hub(%Dataset{} = dataset, repo_id, opts \\ []) do
    config_name = Keyword.get(opts, :config_name, "default")
    split = Keyword.get(opts, :split, "train")
    token = Keyword.get(opts, :token) || get_token()
    private = Keyword.get(opts, :private, false)
    revision = Keyword.get(opts, :revision, "main")
    max_shard_size = Keyword.get(opts, :max_shard_size, @default_max_shard_size)
    commit_message = Keyword.get(opts, :commit_message, "Upload dataset using hf_datasets_ex")

    with :ok <- ensure_authenticated(token),
         :ok <- ensure_repo_exists(repo_id, token, private),
         {:ok, shards} <- create_shards(dataset, max_shard_size),
         :ok <- upload_shards(repo_id, config_name, split, shards, token, revision, commit_message),
         :ok <- update_dataset_card(repo_id, dataset, config_name, split, token, revision) do
      {:ok, "https://huggingface.co/datasets/#{repo_id}"}
    end
  end

  @doc """
  Push a DatasetDict to HuggingFace Hub.

  Uploads all splits.
  """
  @spec push_to_hub(DatasetDict.t(), String.t(), push_opts()) ::
    {:ok, String.t()} | {:error, term()}
  def push_to_hub(%DatasetDict{} = dd, repo_id, opts) do
    config_name = Keyword.get(opts, :config_name, "default")
    token = Keyword.get(opts, :token) || get_token()
    private = Keyword.get(opts, :private, false)

    with :ok <- ensure_authenticated(token),
         :ok <- ensure_repo_exists(repo_id, token, private) do

      results =
        dd.datasets
        |> Enum.map(fn {split_name, dataset} ->
          push_to_hub(dataset, repo_id,
            Keyword.merge(opts, [split: split_name, config_name: config_name]))
        end)

      if Enum.all?(results, &match?({:ok, _}, &1)) do
        {:ok, "https://huggingface.co/datasets/#{repo_id}"}
      else
        {:error, {:partial_upload, results}}
      end
    end
  end

  @doc """
  Delete a dataset config from HuggingFace Hub.

  ## Examples

      :ok = Hub.delete_from_hub("username/my-dataset", "default")

  """
  @spec delete_from_hub(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete_from_hub(repo_id, config_name, opts \\ []) do
    token = Keyword.get(opts, :token) || get_token()
    revision = Keyword.get(opts, :revision, "main")

    with :ok <- ensure_authenticated(token),
         {:ok, files} <- list_config_files(repo_id, config_name, token, revision),
         :ok <- delete_files(repo_id, files, token, revision) do
      :ok
    end
  end

  # Private functions

  defp get_token do
    System.get_env("HF_TOKEN") ||
    System.get_env("HF_HUB_TOKEN") ||
    read_token_file()
  end

  defp read_token_file do
    path = Path.expand("~/.huggingface/token")

    if File.exists?(path) do
      path |> File.read!() |> String.trim()
    end
  end

  defp ensure_authenticated(nil), do: {:error, :no_token}
  defp ensure_authenticated(_token), do: :ok

  defp ensure_repo_exists(repo_id, token, private) do
    case HfHub.Api.repo_info(repo_id, token: token, repo_type: :dataset) do
      {:ok, _} ->
        :ok

      {:error, :not_found} ->
        create_repo(repo_id, token, private)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_repo(repo_id, token, private) do
    # May need to implement this via HTTP if not in hf_hub
    url = "https://huggingface.co/api/repos/create"

    body = Jason.encode!(%{
      type: "dataset",
      name: repo_id,
      private: private
    })

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    case :httpc.request(:post, {to_charlist(url), headers, ~c"application/json", body}, [], []) do
      {:ok, {{_, 200, _}, _, _}} -> :ok
      {:ok, {{_, 201, _}, _, _}} -> :ok
      {:ok, {{_, status, _}, _, response}} -> {:error, {:http_error, status, response}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_shards(%Dataset{items: items}, max_shard_size) do
    if items == [] do
      {:ok, []}
    else
      estimated_row_size = estimate_row_size(hd(items))
      rows_per_shard = max(1, div(max_shard_size, max(1, estimated_row_size)))

      shards =
        items
        |> Enum.chunk_every(rows_per_shard)
        |> Enum.with_index()
        |> Enum.map(fn {shard_items, idx} ->
          # Convert to Parquet bytes
          temp_path = Path.join(System.tmp_dir!(), "shard_#{idx}_#{:rand.uniform(100000)}.parquet")
          temp_dataset = %Dataset{items: shard_items, name: "shard"}

          Export.Parquet.write(temp_dataset, temp_path)
          parquet_data = File.read!(temp_path)
          File.rm!(temp_path)

          %{index: idx, data: parquet_data, num_rows: length(shard_items)}
        end)

      {:ok, shards}
    end
  end

  defp estimate_row_size(item) do
    item
    |> Jason.encode!()
    |> byte_size()
    |> Kernel.*(2)  # Safety factor
  end

  defp upload_shards(_repo_id, _config_name, _split, [], _token, _revision, _message), do: :ok

  defp upload_shards(repo_id, config_name, split, shards, token, revision, message) do
    total = length(shards)

    results =
      shards
      |> Task.async_stream(
        fn shard ->
          filename = shard_filename(config_name, split, shard.index, total)
          upload_file(repo_id, filename, shard.data, token, revision, message)
        end,
        max_concurrency: 4,
        timeout: 300_000
      )
      |> Enum.to_list()

    if Enum.all?(results, &match?({:ok, {:ok, _}}, &1)) do
      :ok
    else
      {:error, {:upload_failed, results}}
    end
  end

  defp shard_filename(config_name, split, index, total) do
    padded_idx = String.pad_leading(to_string(index), 5, "0")
    padded_total = String.pad_leading(to_string(total), 5, "0")
    "#{config_name}/#{split}/data-#{padded_idx}-of-#{padded_total}.parquet"
  end

  defp upload_file(repo_id, path, content, token, revision, message) do
    # Use hf_hub if available, otherwise direct HTTP
    case function_exported?(HfHub.Api, :upload_file, 4) do
      true ->
        HfHub.Api.upload_file(repo_id, path, content,
          token: token,
          revision: revision,
          repo_type: :dataset,
          commit_message: message
        )

      false ->
        upload_file_http(repo_id, path, content, token, revision, message)
    end
  end

  defp upload_file_http(repo_id, path, content, token, _revision, _message) do
    url = "https://huggingface.co/api/datasets/#{repo_id}/upload/main/#{path}"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/octet-stream"}
    ]

    case :httpc.request(:put, {to_charlist(url), headers, ~c"application/octet-stream", content}, [], []) do
      {:ok, {{_, 200, _}, _, _}} -> {:ok, path}
      {:ok, {{_, 201, _}, _, _}} -> {:ok, path}
      {:ok, {{_, status, _}, _, response}} -> {:error, {:http_error, status, response}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_dataset_card(repo_id, dataset, config_name, split, token, revision) do
    card = generate_dataset_card(dataset, config_name, split)
    upload_file(repo_id, "README.md", card, token, revision, "Update dataset card")
    :ok
  end

  defp generate_dataset_card(dataset, config_name, split) do
    num_rows = Dataset.num_items(dataset)
    columns = Dataset.column_names(dataset)

    """
    ---
    dataset_info:
      config_name: #{config_name}
      splits:
        - name: #{split}
          num_examples: #{num_rows}
    ---

    # Dataset Card

    Uploaded using [hf_datasets_ex](https://github.com/North-Shore-AI/hf_datasets_ex).

    ## Dataset Structure

    - **Splits**: #{split}
    - **Rows**: #{num_rows}
    - **Columns**: #{Enum.join(columns, ", ")}
    """
  end

  defp list_config_files(repo_id, config_name, token, _revision) do
    case HfHub.Api.list_repo_tree(repo_id, token: token, repo_type: :dataset, path: config_name) do
      {:ok, files} ->
        paths = Enum.map(files, & &1.path)
        {:ok, paths}
      {:error, :not_found} ->
        {:ok, []}
      error ->
        error
    end
  end

  defp delete_files(_repo_id, [], _token, _revision), do: :ok

  defp delete_files(repo_id, files, token, revision) do
    Enum.each(files, fn path ->
      delete_file(repo_id, path, token, revision)
    end)
    :ok
  end

  defp delete_file(repo_id, path, token, _revision) do
    url = "https://huggingface.co/api/datasets/#{repo_id}/delete/main/#{path}"

    headers = [{"Authorization", "Bearer #{token}"}]

    :httpc.request(:delete, {to_charlist(url), headers}, [], [])
  end
end
```

### 3. Add Dataset Delegates

Add to `lib/dataset_manager/dataset.ex`:

```elixir
@spec push_to_hub(t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
defdelegate push_to_hub(dataset, repo_id, opts \\ []), to: HfDatasetsEx.Hub
```

## TDD Approach

### Step 1: Write Tests First

Create `test/dataset_manager/hub_test.exs`:

```elixir
defmodule HfDatasetsEx.HubTest do
  use ExUnit.Case, async: false

  alias HfDatasetsEx.{Dataset, Hub}

  # Mock tests (don't require token)
  describe "push_to_hub/3 validation" do
    test "returns error without token" do
      dataset = Dataset.from_list([%{"x" => 1}])

      # Clear any env token
      original = System.get_env("HF_TOKEN")
      System.delete_env("HF_TOKEN")
      System.delete_env("HF_HUB_TOKEN")

      assert {:error, :no_token} = Hub.push_to_hub(dataset, "test/repo")

      if original, do: System.put_env("HF_TOKEN", original)
    end
  end

  describe "shard creation" do
    test "creates appropriate number of shards" do
      items = Enum.map(1..100, &%{"x" => &1, "text" => String.duplicate("a", 1000)})
      dataset = Dataset.from_list(items)

      # Small shard size to force multiple shards
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
      dataset = Dataset.from_list([
        %{"text" => "hello", "label" => 1},
        %{"text" => "world", "label" => 0}
      ])

      card = Hub.generate_dataset_card(dataset, "default", "train")

      assert card =~ "num_examples: 2"
      assert card =~ "text, label"
    end
  end

  # Integration tests (require HF_TOKEN)
  @moduletag :hub_integration

  describe "integration" do
    @tag :skip  # Enable manually with valid token
    test "push and delete round-trip" do
      token = System.get_env("HF_TOKEN")
      skip_unless_token(token)

      dataset = Dataset.from_list([
        %{"text" => "test", "id" => 1}
      ])

      repo_id = "hf-datasets-ex-test/integration-#{:rand.uniform(10000)}"

      # Push
      assert {:ok, url} = Hub.push_to_hub(dataset, repo_id, token: token)
      assert url =~ repo_id

      # Cleanup
      assert :ok = Hub.delete_from_hub(repo_id, "default", token: token)
    end
  end

  defp skip_unless_token(nil), do: ExUnit.configure(skip: true)
  defp skip_unless_token(_), do: :ok
end
```

### Step 2: Run Tests

```bash
mix test test/dataset_manager/hub_test.exs
```

### Step 3: Implement Until Tests Pass

### Step 4: Quality Checks

```bash
mix format
mix credo --strict
mix dialyzer
mix test
```

## Acceptance Criteria

- [ ] All tests pass
- [ ] `mix format` produces no changes
- [ ] `mix credo --strict` reports no issues
- [ ] `mix dialyzer` reports no errors
- [ ] Works with HF token from environment
- [ ] Creates shards for large datasets
- [ ] Generates dataset card

## Files to Create/Modify

| File | Action |
|------|--------|
| `lib/dataset_manager/hub.ex` | Create |
| `lib/dataset_manager/dataset.ex` | Add delegate |
| `lib/dataset_manager/dataset_dict.ex` | Add delegate |
| `test/dataset_manager/hub_test.exs` | Create |

## Notes

- Integration tests require a valid HF token
- Tests should be skipped in CI without token
- Consider creating a test organization on HuggingFace
