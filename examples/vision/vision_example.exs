# examples/vision/vision_example.exs
# Run with: mix run examples/vision/vision_example.exs
#
# Demonstrates vision dataset loading and image features.

alias HfDatasetsEx.Features
alias HfDatasetsEx.Loader.Vision

IO.puts("=" <> String.duplicate("=", 60))
IO.puts("Vision Dataset Example")
IO.puts("=" <> String.duplicate("=", 60))
IO.puts("")

opts = [sample_size: 5, decode_images: false]

IO.puts("Loading Caltech101 dataset...")
{:ok, dataset} = Vision.load(:caltech101, opts)

IO.puts("Total items: #{length(dataset.items)}")
IO.puts("Feature columns: #{inspect(Features.column_names(dataset.features))}")
IO.puts("")

first = hd(dataset.items)
image = first.input.image

image_summary =
  cond do
    match?(%Vix.Vips.Image{}, image) ->
      "decoded image"

    is_map(image) ->
      "image bytes/path"

    true ->
      "unknown"
  end

IO.puts("First item ID: #{first.id}")
IO.puts("Label: #{inspect(first.expected)}")
IO.puts("Image value: #{image_summary}")
IO.puts("")

IO.puts("=" <> String.duplicate("=", 60))
IO.puts("Example complete!")
IO.puts("=" <> String.duplicate("=", 60))
