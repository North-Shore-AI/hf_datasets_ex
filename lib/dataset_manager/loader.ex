defmodule HfDatasetsEx.Loader do
  @moduledoc """
  Unified dataset loading with automatic source detection and caching.

  Supports loading from:
  - HuggingFace datasets
  - GitHub repositories
  - Local files
  - HTTP URLs
  """

  alias HfDatasetsEx.{Cache, DataFiles, Dataset, DatasetDict, Format, IterableDataset}

  alias HfDatasetsEx.Loader.{
    Chat,
    Code,
    GSM8K,
    HumanEval,
    Math,
    MMLU,
    Preference,
    Reasoning,
    Rubric,
    Vision
  }

  require Logger

  @dataset_sources %{
    mmlu: {:huggingface, "cais/mmlu", "all"},
    mmlu_stem: {:huggingface, "cais/mmlu", "stem"},
    humaneval: {:huggingface, "openai/openai_humaneval", "default"},
    gsm8k: {:huggingface, "openai/gsm8k", "main"},
    math_500: {:huggingface, "HuggingFaceH4/MATH-500", "default"},
    hendrycks_math: {:huggingface, "EleutherAI/hendrycks_math", "default"},
    deepmath: {:huggingface, "zwhe99/DeepMath-103K", "default"},
    polaris: {:huggingface, "POLARIS-Project/Polaris-Dataset-53K", "default"},
    tulu3_sft: {:huggingface, "allenai/tulu-3-sft-mixture", "default"},
    no_robots: {:huggingface, "HuggingFaceH4/no_robots", "default"},
    hh_rlhf: {:huggingface, "Anthropic/hh-rlhf", "default"},
    helpsteer3: {:huggingface, "nvidia/HelpSteer3", "preference"},
    helpsteer2: {:huggingface, "nvidia/HelpSteer2", "default"},
    ultrafeedback: {:huggingface, "argilla/ultrafeedback-binarized-preferences", "default"},
    arena_140k: {:huggingface, "lmarena-ai/arena-human-preference-140k", "default"},
    tulu3_preference: {:huggingface, "allenai/llama-3.1-tulu-3-8b-preference-mixture", "default"},
    deepcoder: {:huggingface, "agentica-org/DeepCoder-Preview-Dataset", "default"},
    open_thoughts3: {:huggingface, "open-thoughts/OpenThoughts3-1.2M", "default"},
    deepmath_reasoning: {:huggingface, "zwhe99/DeepMath-103K", "default"},
    feedback_collection: {:huggingface, "prometheus-eval/Feedback-Collection", "default"},
    caltech101: {:huggingface, "dpdl-benchmark/caltech101", "default"},
    oxford_flowers102: {:huggingface, "dpdl-benchmark/oxford_flowers102", "default"},
    oxford_iiit_pet: {:huggingface, "dpdl-benchmark/oxford_iiit_pet", "default"},
    stanford_cars: {:huggingface, "tanganke/stanford_cars", "default"}
  }

  @doc """
  Load a dataset by name with automatic caching.

  ## Options
    * `:version` - Specific version (default: "1.0")
    * `:subset` - Subset name for multi-config datasets
    * `:cache` - Use cache (default: true)
    * `:sample_size` - Limit items (default: all)
    * `:source` - Custom source path for local datasets

  ## Examples

      iex> HfDatasetsEx.Loader.load(:mmlu_stem)
      {:ok, %Dataset{name: "mmlu_stem", items: [...], ...}}

      iex> HfDatasetsEx.Loader.load(:humaneval, sample_size: 50)
      {:ok, %Dataset{name: "humaneval", items: [50 items], ...}}

      iex> HfDatasetsEx.Loader.load("custom", source: "path/to/data.jsonl")
      {:ok, %Dataset{name: "custom", ...}}
  """
  @spec load(atom() | String.t(), keyword()) ::
          {:ok, Dataset.t()} | {:error, term()}
  def load(dataset_name, opts \\ []) when is_atom(dataset_name) or is_binary(dataset_name) do
    use_cache = Keyword.get(opts, :cache, true)
    sample_size = Keyword.get(opts, :sample_size)

    cache_key = build_cache_key(dataset_name, opts)

    # Try to load from cache first
    case use_cache && Cache.get(cache_key) do
      {:ok, dataset} ->
        {:ok, maybe_sample(dataset, sample_size)}

      _ ->
        with {:ok, source_spec} <- resolve_source(dataset_name, opts),
             {:ok, dataset} <- fetch_and_parse(source_spec, dataset_name, opts),
             {:ok, validated} <- Dataset.validate(dataset) do
          cache_result =
            if use_cache do
              Cache.put(cache_key, validated)
            else
              :ok
            end

          case cache_result do
            :ok -> {:ok, maybe_sample(validated, sample_size)}
            {:error, reason} -> {:error, reason}
          end
        end
    end
  end

  @doc """
  Load a HuggingFace dataset by repo_id.

  ## Options
    * `:config` - Dataset config/subset name
    * `:split` - Split name (when nil, loads all splits into DatasetDict)
    * `:streaming` - Return IterableDataset for lazy loading (requires split)
    * `:revision` - Git revision (default: \"main\")
    * `:token` - HuggingFace API token

  ## Returns
    * `{:ok, Dataset.t()}` when split is specified and streaming is false
    * `{:ok, DatasetDict.t()}` when split is nil
    * `{:ok, IterableDataset.t()}` when streaming is true
  """
  @spec load_dataset(String.t(), keyword()) ::
          {:ok, Dataset.t() | DatasetDict.t() | IterableDataset.t()} | {:error, term()}
  def load_dataset(repo_id, opts \\ []) when is_binary(repo_id) do
    split = Keyword.get(opts, :split)
    streaming = Keyword.get(opts, :streaming, false)

    cond do
      streaming and is_nil(split) ->
        {:error, :streaming_requires_split}

      streaming ->
        load_dataset_streaming(repo_id, split, opts)

      split ->
        load_dataset_split(repo_id, split, opts)

      true ->
        load_dataset_all_splits(repo_id, opts)
    end
  end

  @doc """
  Invalidate cache for a dataset.
  """
  @spec invalidate_cache(atom() | String.t()) :: :ok
  def invalidate_cache(dataset_name) do
    Cache.invalidate(dataset_name)
  end

  # Private helpers

  defp build_cache_key(dataset_name, _opts) when is_atom(dataset_name) do
    dataset_name
  end

  defp build_cache_key(dataset_name, _opts) when is_binary(dataset_name) do
    {:local, dataset_name}
  end

  defp resolve_source(dataset_name, _opts) when is_atom(dataset_name) do
    case Map.get(@dataset_sources, dataset_name) do
      nil -> {:error, {:unknown_dataset, dataset_name}}
      source -> {:ok, {dataset_name, source}}
    end
  end

  defp resolve_source(dataset_name, opts) when is_binary(dataset_name) do
    source = Keyword.get(opts, :source)

    if source do
      {:ok, {dataset_name, {:local, source}}}
    else
      {:error, {:missing_source, dataset_name}}
    end
  end

  defp fetch_and_parse({dataset_name, source_spec}, _name, opts) do
    case dataset_name do
      name when name in [:mmlu, :mmlu_stem] ->
        MMLU.load(dataset_name, opts)

      :humaneval ->
        HumanEval.load(opts)

      :gsm8k ->
        GSM8K.load(opts)

      name when name in [:math_500, :hendrycks_math, :deepmath, :polaris] ->
        Math.load(name, opts)

      name when name in [:tulu3_sft, :no_robots] ->
        Chat.load(name, opts)

      name
      when name in [
             :hh_rlhf,
             :helpsteer3,
             :helpsteer2,
             :ultrafeedback,
             :arena_140k,
             :tulu3_preference
           ] ->
        Preference.load(name, opts)

      :deepcoder ->
        Code.load(:deepcoder, opts)

      name when name in [:open_thoughts3, :deepmath_reasoning] ->
        Reasoning.load(name, opts)

      :feedback_collection ->
        Rubric.load(:feedback_collection, opts)

      name when name in [:caltech101, :oxford_flowers102, :oxford_iiit_pet, :stanford_cars] ->
        Vision.load(name, opts)

      _ ->
        load_custom(dataset_name, source_spec, opts)
    end
  end

  defp load_custom(name, {:local, path}, opts) do
    case File.read(path) do
      {:ok, content} ->
        parse_jsonl(content, name, opts)

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  defp load_custom(_name, _source, _opts) do
    {:error, :unsupported_source}
  end

  defp parse_jsonl(content, name, _opts) do
    items =
      content
      |> String.split("\n", trim: true)
      |> Stream.map(&Jason.decode!/1)
      |> Stream.with_index()
      |> Enum.map(fn {raw, idx} ->
        %{
          id: "#{name}_#{idx}",
          input: raw["input"] || raw["question"] || raw["text"],
          expected: raw["expected"] || raw["answer"] || raw["label"],
          metadata: Map.get(raw, "metadata", %{})
        }
      end)

    dataset = Dataset.new(to_string(name), "1.0", items, %{source: "local"})
    {:ok, dataset}
  end

  defp maybe_sample(dataset, nil), do: dataset

  defp maybe_sample(dataset, size) when is_integer(size) do
    sampled_items = Enum.take(dataset.items, size)
    %{dataset | items: sampled_items, metadata: Map.put(dataset.metadata, :sampled, size)}
  end

  defp load_dataset_all_splits(repo_id, opts) do
    with {:ok, %{config: config, splits: splits}} <- DataFiles.resolve(repo_id, opts) do
      result =
        splits
        |> Enum.reduce_while({:ok, %{}}, fn {split, files}, {:ok, acc} ->
          case load_dataset_from_files(repo_id, split, files, config, opts) do
            {:ok, dataset} -> {:cont, {:ok, Map.put(acc, split, dataset)}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      case result do
        {:ok, datasets} -> {:ok, DatasetDict.new(datasets)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp load_dataset_split(repo_id, split, opts) do
    split_str = to_string(split)

    with {:ok, %{config: config, splits: splits}} <- DataFiles.resolve(repo_id, opts),
         {:ok, dataset} <-
           load_dataset_from_files(repo_id, split_str, splits[split_str], config, opts) do
      {:ok, dataset}
    end
  end

  defp load_dataset_streaming(repo_id, split, opts) do
    split_str = to_string(split)

    with {:ok, %{config: config, splits: splits}} <- DataFiles.resolve(repo_id, opts),
         files when is_list(files) <- Map.get(splits, split_str),
         true <- files != [] do
      stream = build_stream(repo_id, files, opts)

      iterable =
        IterableDataset.from_stream(stream,
          name: repo_id,
          info: %{
            source: "huggingface:#{repo_id}",
            split: split_str,
            config: config,
            streaming: true
          }
        )

      {:ok, iterable}
    else
      false -> {:error, {:split_not_found, split}}
      nil -> {:error, {:split_not_found, split}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_dataset_from_files(repo_id, split, files, config, opts) when is_list(files) do
    case load_items_from_files(repo_id, files, opts) do
      {:ok, items} ->
        dataset =
          Dataset.new(
            repo_id,
            "1.0",
            items,
            %{
              source: "huggingface:#{repo_id}",
              split: split,
              config: config
            }
          )

        {:ok, dataset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_dataset_from_files(_repo_id, _split, nil, _config, _opts) do
    {:error, :no_files_found}
  end

  defp load_items_from_files(repo_id, files, opts) do
    revision = Keyword.get(opts, :revision, "main")
    token = Keyword.get(opts, :token)

    results =
      Enum.map(files, fn file ->
        download_opts = [
          repo_id: repo_id,
          filename: file.path,
          repo_type: :dataset,
          revision: revision,
          token: token,
          extract: true
        ]

        with {:ok, path} <- HfHub.Download.hf_hub_download(download_opts) do
          parse_downloaded_path(path, file.format)
        end
      end)

    merge_parse_results(results)
  end

  defp parse_downloaded_path(path, format_hint) do
    paths =
      if File.dir?(path) do
        Path.wildcard(Path.join(path, "**/*"))
        |> Enum.reject(&File.dir?/1)
      else
        [path]
      end

    results =
      paths
      |> Enum.map(fn file_path ->
        format = if format_hint == :unknown, do: Format.detect(file_path), else: format_hint

        parser = Format.parser_for(format)

        if is_nil(parser) do
          {:ok, []}
        else
          apply(parser, :parse, [file_path])
        end
      end)

    merge_parse_results(results)
  end

  defp merge_parse_results(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn result, {:ok, acc} ->
      case result do
        {:ok, items} -> {:cont, {:ok, acc ++ items}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp build_stream(repo_id, files, opts) do
    files
    |> Enum.map(&stream_file(repo_id, &1, opts))
    |> Stream.concat()
  end

  defp stream_file(repo_id, file, opts) do
    case file.format do
      :jsonl -> stream_jsonl(repo_id, file.path, opts)
      :parquet -> stream_parquet(repo_id, file.path, opts)
      _ -> stream_fallback(repo_id, file, opts)
    end
  end

  defp stream_jsonl(repo_id, path, opts) do
    revision = Keyword.get(opts, :revision, "main")
    token = Keyword.get(opts, :token)

    {:ok, byte_stream} =
      HfHub.Download.download_stream(
        repo_id: repo_id,
        filename: path,
        repo_type: :dataset,
        revision: revision,
        token: token
      )

    Format.JSONL.parse_stream(byte_stream)
  end

  defp stream_parquet(repo_id, path, opts) do
    Logger.warning("Parquet streaming is limited; loading file in batches.")

    revision = Keyword.get(opts, :revision, "main")
    token = Keyword.get(opts, :token)
    batch_size = Keyword.get(opts, :batch_size, 1000)

    {:ok, local_path} =
      HfHub.Download.hf_hub_download(
        repo_id: repo_id,
        filename: path,
        repo_type: :dataset,
        revision: revision,
        token: token,
        extract: true
      )

    local_path
    |> expand_data_paths()
    |> Enum.map(&Format.Parquet.stream_rows(&1, batch_size: batch_size))
    |> Stream.concat()
  end

  defp stream_fallback(repo_id, file, opts) do
    case load_items_from_files(repo_id, [file], opts) do
      {:ok, items} -> Stream.map(items, & &1)
      {:error, _} -> Stream.map([], & &1)
    end
  end

  defp expand_data_paths(path) do
    if File.dir?(path) do
      Path.wildcard(Path.join(path, "**/*"))
      |> Enum.reject(&File.dir?/1)
      |> Enum.filter(&(Format.detect(&1) in [:parquet, :jsonl, :json, :csv]))
    else
      [path]
    end
  end
end
