# Custom Dataset Builder Example
# Demonstrates defining and building custom datasets

alias HfDatasetsEx.{Builder, Dataset, DatasetInfo, Features}
alias HfDatasetsEx.Features.{Value, ClassLabel}
alias HfDatasetsEx.{BuilderConfig, DownloadManager, SplitGenerator}

IO.puts("=== Custom Dataset Builder Example ===\n")

# Define a custom dataset builder
defmodule SentimentDataset do
  use HfDatasetsEx.DatasetBuilder

  @impl true
  def info do
    DatasetInfo.new(
      description: "A simple sentiment analysis dataset",
      features:
        Features.new(%{
          "text" => %Value{dtype: :string},
          "sentiment" => ClassLabel.new(names: ["negative", "neutral", "positive"])
        })
    )
  end

  @impl true
  def configs do
    [
      BuilderConfig.new(name: "default", description: "All data"),
      BuilderConfig.new(name: "binary", description: "Only positive/negative")
    ]
  end

  @impl true
  def default_config_name, do: "default"

  @impl true
  def split_generators(_dl_manager, config) do
    # In a real builder, you'd download files here
    # For this example, we generate data directly
    [
      SplitGenerator.new(:train, %{config: config.name, split: :train}),
      SplitGenerator.new(:test, %{config: config.name, split: :test})
    ]
  end

  @impl true
  def generate_examples(%{config: config_name, split: split}, _split_name) do
    # Generate sample data based on config and split
    base_data = [
      {"I love this product!", "positive"},
      {"This is terrible", "negative"},
      {"It's okay I guess", "neutral"},
      {"Amazing experience!", "positive"},
      {"Worst purchase ever", "negative"},
      {"Nothing special", "neutral"},
      {"Highly recommend!", "positive"},
      {"Complete waste", "negative"}
    ]

    # Filter for binary config
    data =
      if config_name == "binary" do
        Enum.filter(base_data, fn {_, label} -> label != "neutral" end)
      else
        base_data
      end

    # Split into train/test
    {train, test} = Enum.split(data, div(length(data) * 8, 10))
    items = if split == :train, do: train, else: test

    # Generate examples with indices
    items
    |> Enum.with_index()
    |> Enum.map(fn {{text, sentiment}, idx} ->
      label_idx =
        case sentiment do
          "negative" -> 0
          "neutral" -> 1
          "positive" -> 2
        end

      {idx, %{"text" => text, "sentiment" => label_idx}}
    end)
  end
end

# Build with default config
IO.puts("=== Building with Default Config ===")
{:ok, dd} = Builder.build(SentimentDataset)
IO.puts("Built DatasetDict with splits: #{inspect(HfDatasetsEx.DatasetDict.split_names(dd))}")
IO.puts("Train items: #{Dataset.num_items(dd.datasets["train"])}")
IO.puts("Test items: #{Dataset.num_items(dd.datasets["test"])}")

train = dd.datasets["train"]
IO.puts("\nSample train items:")

train.items
|> Enum.take(3)
|> Enum.each(fn item ->
  IO.puts("  #{inspect(item)}")
end)

# Build with binary config
IO.puts("\n=== Building with Binary Config ===")
{:ok, binary_dd} = Builder.build(SentimentDataset, config_name: "binary")
IO.puts("Binary config train items: #{Dataset.num_items(binary_dd.datasets["train"])}")

# Build single split
IO.puts("\n=== Building Single Split ===")
{:ok, train_only} = Builder.build(SentimentDataset, split: :train)
IO.puts("Train-only dataset: #{Dataset.num_items(train_only)} items")

# Access dataset info
IO.puts("\n=== Dataset Info ===")
info = SentimentDataset.info()
IO.puts("Description: #{info.description}")
IO.puts("Features: #{inspect(info.features.schema)}")

IO.puts("\n=== Custom Builder Example Complete ===")
