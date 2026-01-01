# Gap Analysis: Hub Integration

## Overview

The Python `datasets` library has comprehensive HuggingFace Hub integration for pushing, deleting, and managing datasets. The Elixir port only supports downloading/loading via `hf_hub`.

## Current Elixir Implementation

| Operation | Status | Module |
|-----------|--------|--------|
| Download datasets | ✅ | `HfDatasetsEx.Loader` via `hf_hub` |
| List configs | ✅ | `HfDatasetsEx.DataFiles` via `HfHub.Api` |
| List splits | ✅ | `HfDatasetsEx.DataFiles` via `HfHub.Api` |
| Authenticate | ✅ | Token passed to `hf_hub` |
| Push to Hub | ❌ | Not implemented |
| Delete from Hub | ❌ | Not implemented |
| Update metadata | ❌ | Not implemented |

## Missing Hub Operations

### P2 - push_to_hub/2

The most requested missing feature for dataset sharing.

```python
# Python signature
Dataset.push_to_hub(
    repo_id: str,
    config_name: str = "default",
    split: str | None = None,
    private: bool = False,
    token: str | None = None,
    branch: str | None = None,
    max_shard_size: str | int = "500MB",
    num_shards: int | None = None,
    embed_external_files: bool = True,
    commit_message: str | None = None,
    commit_description: str | None = None,
)
```

```elixir
# Proposed Elixir
defmodule HfDatasetsEx.Hub do
  @type push_opts :: [
    config_name: String.t(),
    split: String.t() | nil,
    private: boolean(),
    token: String.t() | nil,
    revision: String.t(),
    max_shard_size: non_neg_integer(),
    num_shards: non_neg_integer() | nil,
    commit_message: String.t() | nil,
    commit_description: String.t() | nil
  ]

  @spec push_to_hub(HfDatasetsEx.Dataset.t(), String.t(), push_opts()) ::
    {:ok, String.t()} | {:error, term()}
  def push_to_hub(%Dataset{} = dataset, repo_id, opts \\ []) do
    config_name = Keyword.get(opts, :config_name, "default")
    split = Keyword.get(opts, :split, "train")
    token = Keyword.get(opts, :token) || get_token_from_env()
    private = Keyword.get(opts, :private, false)
    revision = Keyword.get(opts, :revision, "main")
    max_shard_size = Keyword.get(opts, :max_shard_size, 500 * 1024 * 1024)

    with :ok <- ensure_repo_exists(repo_id, token, private),
         {:ok, shards} <- shard_dataset(dataset, max_shard_size),
         {:ok, _} <- upload_shards(repo_id, config_name, split, shards, token, revision),
         :ok <- update_readme(repo_id, dataset, token, revision) do
      {:ok, "https://huggingface.co/datasets/#{repo_id}"}
    end
  end

  defp ensure_repo_exists(repo_id, token, private) do
    case HfHub.Api.repo_info(repo_id, token: token, repo_type: :dataset) do
      {:ok, _} -> :ok
      {:error, :not_found} ->
        HfHub.Api.create_repo(repo_id,
          token: token,
          repo_type: :dataset,
          private: private)
      error -> error
    end
  end

  defp shard_dataset(dataset, max_shard_size) do
    # Split dataset into shards based on size
    items = dataset.items
    estimated_row_size = estimate_row_size(hd(items))
    rows_per_shard = max(1, div(max_shard_size, estimated_row_size))

    shards =
      items
      |> Enum.chunk_every(rows_per_shard)
      |> Enum.with_index()
      |> Enum.map(fn {shard_items, idx} ->
        %{
          index: idx,
          items: shard_items,
          parquet_data: to_parquet_binary(shard_items)
        }
      end)

    {:ok, shards}
  end

  defp upload_shards(repo_id, config_name, split, shards, token, revision) do
    total = length(shards)

    results =
      shards
      |> Task.async_stream(fn shard ->
        filename = "#{config_name}/#{split}/#{shard_filename(shard.index, total)}"

        HfHub.Api.upload_file(
          repo_id,
          filename,
          shard.parquet_data,
          token: token,
          revision: revision,
          repo_type: :dataset
        )
      end, max_concurrency: 4, timeout: 300_000)
      |> Enum.to_list()

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:ok, results}
    else
      {:error, {:upload_failed, results}}
    end
  end

  defp shard_filename(index, total) do
    padded_index = String.pad_leading(to_string(index), 5, "0")
    padded_total = String.pad_leading(to_string(total), 5, "0")
    "data-#{padded_index}-of-#{padded_total}.parquet"
  end

  defp update_readme(repo_id, dataset, token, revision) do
    # Generate or update README.md with dataset card
    card_content = generate_dataset_card(dataset)

    HfHub.Api.upload_file(
      repo_id,
      "README.md",
      card_content,
      token: token,
      revision: revision,
      repo_type: :dataset
    )
  end

  defp generate_dataset_card(dataset) do
    """
    ---
    dataset_info:
      features:
    #{format_features_yaml(dataset.features)}
      splits:
        - name: train
          num_examples: #{length(dataset.items)}
    ---

    # Dataset Card

    This dataset was uploaded using `hf_datasets_ex`.

    ## Dataset Description

    #{dataset.metadata[:description] || "No description provided."}
    """
  end
end
```

### P2 - delete_from_hub/2

```python
# Python (in hub.py)
def delete_from_hub(
    repo_id: str,
    config_name: str,
    revision: str | None = None,
    token: str | None = None,
)
```

```elixir
# Proposed Elixir
@spec delete_from_hub(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
def delete_from_hub(repo_id, config_name, opts \\ []) do
  token = Keyword.get(opts, :token) || get_token_from_env()
  revision = Keyword.get(opts, :revision, "main")

  # List files in the config directory
  {:ok, files} = HfHub.Api.list_repo_tree(repo_id,
    token: token,
    revision: revision,
    repo_type: :dataset,
    path: config_name
  )

  # Delete each file
  Enum.each(files, fn file ->
    HfHub.Api.delete_file(repo_id, file.path,
      token: token,
      revision: revision,
      repo_type: :dataset
    )
  end)

  :ok
end
```

### P2 - DatasetDict.push_to_hub/2

Push all splits at once.

```elixir
defmodule HfDatasetsEx.DatasetDict do
  @spec push_to_hub(t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def push_to_hub(%__MODULE__{} = dd, repo_id, opts \\ []) do
    config_name = Keyword.get(opts, :config_name, "default")

    results =
      dd.datasets
      |> Enum.map(fn {split_name, dataset} ->
        Hub.push_to_hub(dataset, repo_id,
          Keyword.merge(opts, [split: split_name, config_name: config_name]))
      end)

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:ok, "https://huggingface.co/datasets/#{repo_id}"}
    else
      {:error, {:partial_upload, results}}
    end
  end
end
```

### P3 - Dataset Card Management

```elixir
defmodule HfDatasetsEx.Hub.DatasetCard do
  @type t :: %__MODULE__{
    description: String.t() | nil,
    citation: String.t() | nil,
    license: String.t() | nil,
    language: [String.t()],
    tags: [String.t()],
    features: map(),
    splits: [map()]
  }

  defstruct [
    :description,
    :citation,
    :license,
    language: [],
    tags: [],
    features: %{},
    splits: []
  ]

  @spec from_dataset(HfDatasetsEx.Dataset.t()) :: t()
  def from_dataset(%Dataset{} = dataset) do
    %__MODULE__{
      features: Features.to_map(dataset.features),
      splits: [%{name: "train", num_examples: length(dataset.items)}]
    }
  end

  @spec to_markdown(t()) :: String.t()
  def to_markdown(%__MODULE__{} = card) do
    # Generate README.md content
  end

  @spec push(t(), String.t(), keyword()) :: :ok | {:error, term()}
  def push(%__MODULE__{} = card, repo_id, opts \\ []) do
    content = to_markdown(card)
    token = Keyword.get(opts, :token)

    HfHub.Api.upload_file(repo_id, "README.md", content,
      token: token,
      repo_type: :dataset
    )
  end
end
```

## Required hf_hub Additions

The `hf_hub` library may need these additions:

```elixir
# Functions needed in HfHub.Api
HfHub.Api.create_repo(repo_id, opts)
HfHub.Api.delete_repo(repo_id, opts)
HfHub.Api.upload_file(repo_id, path, content, opts)
HfHub.Api.delete_file(repo_id, path, opts)
HfHub.Api.create_commit(repo_id, operations, opts)
```

Check if these exist in `hf_hub` v0.1.1. If not, either:
1. Add them to `hf_hub`
2. Implement directly in `hf_datasets_ex` using HTTP client

## Authentication

```elixir
defmodule HfDatasetsEx.Hub.Auth do
  @doc """
  Get HuggingFace token from environment or config.

  Checks in order:
  1. HF_TOKEN environment variable
  2. HF_HUB_TOKEN environment variable
  3. ~/.huggingface/token file
  4. Application config
  """
  @spec get_token() :: String.t() | nil
  def get_token do
    System.get_env("HF_TOKEN") ||
    System.get_env("HF_HUB_TOKEN") ||
    read_token_file() ||
    Application.get_env(:hf_datasets_ex, :hf_token)
  end

  defp read_token_file do
    token_path = Path.expand("~/.huggingface/token")

    if File.exists?(token_path) do
      token_path
      |> File.read!()
      |> String.trim()
    end
  end
end
```

## Files to Create

| File | Purpose |
|------|---------|
| `lib/dataset_manager/hub.ex` | Main Hub operations module |
| `lib/dataset_manager/hub/auth.ex` | Authentication utilities |
| `lib/dataset_manager/hub/dataset_card.ex` | Dataset card generation |
| `lib/dataset_manager/hub/upload.ex` | Upload/shard logic |
| `test/dataset_manager/hub_test.exs` | Hub operation tests |

## Testing Considerations

Hub operations are difficult to test without real API access:

1. **Mock Tests**: Use `bypass` to mock HuggingFace API
2. **Integration Tests**: Tagged tests that run against real Hub (require token)
3. **Sandbox Repo**: Create a test dataset repo for CI

```elixir
# test/dataset_manager/hub_test.exs
defmodule HfDatasetsEx.HubTest do
  use ExUnit.Case, async: false

  @moduletag :hub_integration

  @test_repo "hf-datasets-ex-test/integration-test"

  setup do
    token = System.get_env("HF_TOKEN")

    if is_nil(token) do
      :skip
    else
      {:ok, token: token}
    end
  end

  test "push and delete dataset", %{token: token} do
    dataset = Dataset.from_list([%{"text" => "hello"}])

    # Push
    assert {:ok, url} = Hub.push_to_hub(dataset, @test_repo, token: token)
    assert url =~ @test_repo

    # Verify by loading
    assert {:ok, loaded} = Loader.load_dataset(@test_repo, token: token)
    assert Dataset.num_items(loaded) == 1

    # Cleanup
    assert :ok = Hub.delete_from_hub(@test_repo, "default", token: token)
  end
end
```

## Error Handling

```elixir
defmodule HfDatasetsEx.Hub.Error do
  defexception [:message, :reason, :status_code]

  @type t :: %__MODULE__{
    message: String.t(),
    reason: atom(),
    status_code: non_neg_integer() | nil
  }

  def unauthorized do
    %__MODULE__{
      message: "Authentication required. Set HF_TOKEN environment variable.",
      reason: :unauthorized,
      status_code: 401
    }
  end

  def repo_not_found(repo_id) do
    %__MODULE__{
      message: "Repository not found: #{repo_id}",
      reason: :not_found,
      status_code: 404
    }
  end

  def quota_exceeded do
    %__MODULE__{
      message: "Storage quota exceeded. Upgrade your HuggingFace account.",
      reason: :quota_exceeded,
      status_code: 507
    }
  end
end
```

## Dependencies

No new dependencies required. Uses existing `hf_hub` for API calls.

May need to verify/extend `hf_hub` API coverage for:
- `create_repo`
- `upload_file`
- `delete_file`
- `create_commit`
