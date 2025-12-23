defmodule HfDatasetsEx.Source do
  @moduledoc """
  Behaviour for dataset sources.

  Sources are responsible for locating and fetching raw data files.
  They do NOT parse the data - that's the Format layer's job.

  ## Implementations

  - `HfDatasetsEx.Source.Local` - Local filesystem
  - `HfDatasetsEx.Source.HuggingFace` - HuggingFace Hub

  ## Example

      # List files from local directory
      {:ok, files} = Source.Local.list_files("./data", [])

      # Download from HuggingFace
      {:ok, path} = Source.HuggingFace.download("openai/gsm8k", "test.parquet", split: "test")

  """

  @type file_info :: %{
          path: String.t(),
          size: non_neg_integer() | nil,
          format: atom()
        }

  @type fetch_opts :: [
          split: String.t(),
          config: String.t(),
          token: String.t()
        ]

  @doc "List available files for a dataset"
  @callback list_files(dataset_ref :: String.t(), opts :: fetch_opts()) ::
              {:ok, [file_info()]} | {:error, term()}

  @doc "Download a file to local cache, return path"
  @callback download(dataset_ref :: String.t(), file_path :: String.t(), opts :: fetch_opts()) ::
              {:ok, local_path :: String.t()} | {:error, term()}

  @doc "Stream file contents"
  @callback stream(dataset_ref :: String.t(), file_path :: String.t(), opts :: fetch_opts()) ::
              {:ok, Enumerable.t()} | {:error, term()}

  @doc "Check if dataset exists"
  @callback exists?(dataset_ref :: String.t(), opts :: fetch_opts()) :: boolean()

  @doc """
  Detect format from file extension.
  """
  @spec detect_format(String.t()) :: atom()
  def detect_format(path) when is_binary(path) do
    case Path.extname(path) |> String.downcase() do
      ".parquet" -> :parquet
      ".jsonl" -> :jsonl
      ".jsonlines" -> :jsonl
      ".json" -> :json
      ".csv" -> :csv
      ".txt" -> :text
      ".arrow" -> :arrow
      _ -> :unknown
    end
  end
end
