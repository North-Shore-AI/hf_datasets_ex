defmodule HfDatasetsEx.DatasetBuilder do
  @moduledoc """
  Behaviour for defining custom dataset builders.

  ## Usage

      defmodule MyDataset do
        use HfDatasetsEx.DatasetBuilder

        @impl true
        def info do
          DatasetInfo.new(
            description: "My custom dataset",
            features: Features.new(%{
              "text" => %Value{dtype: :string},
              "label" => %ClassLabel{names: ["neg", "pos"]}
            })
          )
        end

        @impl true
        def split_generators(dl_manager, _config) do
          {:ok, train_path} = DownloadManager.download(dl_manager, @train_url)
          {:ok, test_path} = DownloadManager.download(dl_manager, @test_url)

          [
            SplitGenerator.new(:train, train_path),
            SplitGenerator.new(:test, test_path)
          ]
        end

        @impl true
        def generate_examples(filepath, _split) do
          filepath
          |> File.stream!()
          |> Stream.with_index()
          |> Stream.map(fn {line, idx} -> {idx, Jason.decode!(line)} end)
        end
      end

  """

  alias HfDatasetsEx.{BuilderConfig, DatasetInfo, DownloadManager, SplitGenerator}

  @callback info() :: DatasetInfo.t()
  @callback configs() :: [BuilderConfig.t()]
  @callback default_config_name() :: String.t() | nil
  @callback split_generators(DownloadManager.t(), BuilderConfig.t()) :: [SplitGenerator.t()]
  @callback generate_examples(map(), atom()) :: Enumerable.t()

  @optional_callbacks [configs: 0, default_config_name: 0]

  defmacro __using__(_opts) do
    quote do
      @behaviour HfDatasetsEx.DatasetBuilder

      alias HfDatasetsEx.{
        BuilderConfig,
        DatasetInfo,
        DownloadManager,
        Features,
        SplitGenerator
      }

      alias HfDatasetsEx.Features.{ClassLabel, Sequence, Value}

      @impl true
      def configs, do: [BuilderConfig.new()]

      @impl true
      def default_config_name, do: nil

      defoverridable configs: 0, default_config_name: 0
    end
  end
end
