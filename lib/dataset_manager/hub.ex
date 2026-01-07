defmodule HfDatasetsEx.Hub do
  @moduledoc """
  HuggingFace Hub operations for datasets.
  """

  alias HfDatasetsEx.{Dataset, DatasetDict, Export}
  alias HfHub.{Auth, Config, HTTP}

  @type push_opts :: [
          config_name: String.t(),
          split: String.t() | nil,
          private: boolean(),
          token: String.t() | nil,
          revision: String.t(),
          max_shard_size: non_neg_integer(),
          commit_message: String.t() | nil
        ]

  @default_max_shard_size 500 * 1024 * 1024

  @doc """
  Push a dataset to HuggingFace Hub.

  Supports both `Dataset` and `DatasetDict` values.

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
  @spec push_to_hub(Dataset.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def push_to_hub(%Dataset{} = dataset, repo_id) do
    push_to_hub(dataset, repo_id, [])
  end

  @spec push_to_hub(DatasetDict.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def push_to_hub(%DatasetDict{} = dd, repo_id) do
    push_to_hub(dd, repo_id, [])
  end

  @spec push_to_hub(Dataset.t(), String.t(), push_opts()) ::
          {:ok, String.t()} | {:error, term()}
  def push_to_hub(%Dataset{} = dataset, repo_id, opts) do
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
         :ok <-
           upload_shards(repo_id, config_name, split, shards, token, revision, commit_message),
         :ok <- update_dataset_card(repo_id, dataset, config_name, split, token, revision) do
      {:ok, repo_url(repo_id)}
    end
  end

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
          push_to_hub(
            dataset,
            repo_id,
            Keyword.merge(opts, split: split_name, config_name: config_name, token: token)
          )
        end)

      if Enum.all?(results, &match?({:ok, _}, &1)) do
        {:ok, repo_url(repo_id)}
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
         {:ok, files} <- list_config_files(repo_id, config_name, token, revision) do
      delete_files(repo_id, files, token, revision)
    end
  end

  defp repo_url(repo_id), do: "#{Config.endpoint()}/datasets/#{repo_id}"

  # Token helpers

  defp get_token do
    Application.get_env(:hf_hub, :token) ||
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
  defp ensure_authenticated(""), do: {:error, :no_token}
  defp ensure_authenticated(_token), do: :ok

  defp ensure_repo_exists(repo_id, token, private) do
    case HfHub.Api.dataset_info(repo_id, token: token) do
      {:ok, _} ->
        :ok

      {:error, :not_found} ->
        create_repo(repo_id, token, private)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_repo(repo_id, token, private) do
    {name, organization} = split_repo_id(repo_id)

    body =
      %{
        type: "dataset",
        name: name,
        private: private
      }
      |> maybe_put(:organization, organization)

    case HTTP.post("/api/repos/create", body, token: token) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp split_repo_id(repo_id) do
    case String.split(repo_id, "/", parts: 2) do
      [name] -> {name, nil}
      [organization, name] -> {name, organization}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc false
  @spec create_shards(Dataset.t(), non_neg_integer()) ::
          {:ok, list(map())} | {:error, term()}
  def create_shards(%Dataset{items: []}, _max_shard_size), do: {:ok, []}

  def create_shards(%Dataset{items: items} = dataset, max_shard_size) do
    estimated_row_size = estimate_row_size(hd(items))
    rows_per_shard = max(1, div(max_shard_size, max(1, estimated_row_size)))

    items
    |> Enum.chunk_every(rows_per_shard)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {shard_items, idx}, {:ok, acc} ->
      case build_parquet_shard(dataset, shard_items, idx) do
        {:ok, shard} -> {:cont, {:ok, [shard | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, shards} -> {:ok, Enum.reverse(shards)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_parquet_shard(%Dataset{} = dataset, shard_items, idx) do
    temp_path = Path.join(System.tmp_dir!(), "shard_#{idx}_#{unique_suffix()}.parquet")
    temp_dataset = %Dataset{dataset | items: shard_items}

    try do
      with :ok <- Export.to_parquet(temp_dataset, temp_path),
           {:ok, parquet_data} <- File.read(temp_path) do
        {:ok, %{index: idx, data: parquet_data, num_rows: length(shard_items)}}
      end
    after
      _ = File.rm(temp_path)
    end
  end

  defp unique_suffix do
    Integer.to_string(:erlang.unique_integer([:positive]))
  end

  defp estimate_row_size(item) do
    case Jason.encode(item) do
      {:ok, json} -> byte_size(json) * 2
      _ -> item |> :erlang.term_to_binary() |> byte_size() |> Kernel.*(2)
    end
  rescue
    _ -> item |> :erlang.term_to_binary() |> byte_size() |> Kernel.*(2)
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

    errors =
      Enum.filter(results, fn
        {:ok, {:ok, _}} -> false
        {:ok, :ok} -> false
        _ -> true
      end)

    if errors == [] do
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
    if function_exported?(HfHub.Api, :upload_file, 4) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(HfHub.Api, :upload_file, [
        repo_id,
        path,
        content,
        [
          token: token,
          revision: revision,
          repo_type: :dataset,
          commit_message: message
        ]
      ])
    else
      upload_file_http(repo_id, path, content, token, revision, message)
    end
  end

  defp upload_file_http(repo_id, path, content, token, revision, message) do
    endpoint = Config.endpoint()
    encoded_path = encode_path(path)

    url =
      "#{endpoint}/api/datasets/#{repo_id}/upload/#{revision}/#{encoded_path}" <>
        maybe_commit_message(message)

    headers =
      request_headers(token, [
        {"content-type", "application/octet-stream"}
      ])

    http_opts = Config.http_opts()
    receive_timeout = max(Keyword.get(http_opts, :receive_timeout, 30_000), 300_000)

    case Req.request(
           method: :put,
           url: url,
           headers: headers,
           body: content,
           receive_timeout: receive_timeout
         ) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> {:ok, path}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp encode_path(path) do
    path
    |> String.split("/")
    |> Enum.map_join("/", &URI.encode/1)
  end

  defp maybe_commit_message(nil), do: ""
  defp maybe_commit_message(""), do: ""

  defp maybe_commit_message(message) do
    "?commit_message=" <> URI.encode_www_form(message)
  end

  defp request_headers(token, extra_headers \\ []) do
    {:ok, auth_headers} = Auth.auth_headers(token: token)
    [{"user-agent", "hf_datasets_ex/0.1.1"} | auth_headers] ++ extra_headers
  end

  defp update_dataset_card(repo_id, dataset, config_name, split, token, revision) do
    card = generate_dataset_card(dataset, config_name, split)

    case upload_file(repo_id, "README.md", card, token, revision, "Update dataset card") do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  @spec generate_dataset_card(Dataset.t(), String.t(), String.t()) :: String.t()
  def generate_dataset_card(dataset, config_name, split) do
    num_rows = Dataset.num_items(dataset)

    columns =
      dataset
      |> Dataset.column_names()
      |> Enum.map(&to_string/1)
      |> Enum.sort()

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

    - Splits: #{split}
    - Rows: #{num_rows}
    - Columns: #{Enum.join(columns, ", ")}
    """
  end

  defp list_config_files(repo_id, config_name, token, revision) do
    case HfHub.Api.list_repo_tree(repo_id,
           token: token,
           repo_type: :dataset,
           revision: revision,
           path_in_repo: config_name,
           recursive: true
         ) do
      {:ok, files} ->
        paths =
          files
          |> Enum.filter(&(&1.type == :file))
          |> Enum.map(& &1.path)

        {:ok, paths}

      {:error, :not_found} ->
        {:ok, []}

      error ->
        error
    end
  end

  defp delete_files(_repo_id, [], _token, _revision), do: :ok

  defp delete_files(repo_id, files, token, revision) do
    results =
      files
      |> Task.async_stream(
        fn path ->
          delete_file(repo_id, path, token, revision)
        end,
        max_concurrency: 4,
        timeout: 300_000
      )
      |> Enum.to_list()

    errors =
      Enum.filter(results, fn
        {:ok, :ok} -> false
        _ -> true
      end)

    if errors == [] do
      :ok
    else
      {:error, {:delete_failed, results}}
    end
  end

  defp delete_file(repo_id, path, token, revision) do
    endpoint = Config.endpoint()
    encoded_path = encode_path(path)
    url = "#{endpoint}/api/datasets/#{repo_id}/delete/#{revision}/#{encoded_path}"
    headers = request_headers(token)

    case Req.request(method: :delete, url: url, headers: headers) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end
end
