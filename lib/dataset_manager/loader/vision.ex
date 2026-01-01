defmodule HfDatasetsEx.Loader.Vision do
  @moduledoc """
  Loader for vision datasets used in VLM recipes.

  Supports:
    - caltech101 (dpdl-benchmark/caltech101)
    - oxford_flowers102 (dpdl-benchmark/oxford_flowers102)
    - oxford_iiit_pet (dpdl-benchmark/oxford_iiit_pet)
    - stanford_cars (tanganke/stanford_cars)
  """

  alias HfDatasetsEx.{Dataset, Features}
  alias HfDatasetsEx.Features.{ClassLabel, Image, Value}
  alias HfDatasetsEx.Fetcher.HuggingFace
  alias HfDatasetsEx.Media.Image, as: ImageDecoder

  @datasets %{
    caltech101: %{
      repo_id: "dpdl-benchmark/caltech101",
      num_classes: 102,
      has_species: false
    },
    oxford_flowers102: %{
      repo_id: "dpdl-benchmark/oxford_flowers102",
      num_classes: 102,
      has_species: false
    },
    oxford_iiit_pet: %{
      repo_id: "dpdl-benchmark/oxford_iiit_pet",
      num_classes: 37,
      has_species: true
    },
    stanford_cars: %{
      repo_id: "tanganke/stanford_cars",
      num_classes: 196,
      has_species: false
    }
  }

  @doc """
  Load a vision dataset.

  ## Options
    * `:split` - Dataset split (default: "train")
    * `:sample_size` - Limit number of items
    * `:decode_images` - Decode image bytes with Vix (default: false)
    * `:token` - HuggingFace API token
  """
  @spec load(atom(), keyword()) :: {:ok, Dataset.t()} | {:error, term()}
  def load(dataset_name, opts \\ []) when is_atom(dataset_name) do
    case Map.get(@datasets, dataset_name) do
      nil ->
        {:error, {:unknown_vision_dataset, dataset_name}}

      config ->
        load_from_huggingface(dataset_name, config, opts)
    end
  end

  defp load_from_huggingface(dataset_name, config, opts) do
    split = Keyword.get(opts, :split, "train") |> to_string()
    sample_size = Keyword.get(opts, :sample_size)
    token = Keyword.get(opts, :token)
    decode_images = Keyword.get(opts, :decode_images, false)

    case HuggingFace.fetch(config.repo_id, split: split, token: token) do
      {:ok, raw_data} ->
        items = parse_vision_data(raw_data, dataset_name, decode_images, config)
        items = if sample_size, do: Enum.take(items, sample_size), else: items

        dataset =
          Dataset.new(
            to_string(dataset_name),
            "1.0",
            items,
            %{
              source: "huggingface:#{config.repo_id}",
              split: split,
              domain: "vision",
              task_type: "image_classification",
              num_classes: config.num_classes
            },
            build_features(config, decode_images)
          )

        {:ok, dataset}

      {:error, reason} ->
        {:error, {:huggingface_fetch_failed, reason}}
    end
  end

  defp parse_vision_data(raw_data, dataset_name, decode_images, config) do
    raw_data
    |> Enum.with_index()
    |> Enum.map(fn {row, idx} ->
      build_vision_item(row, dataset_name, decode_images, config, idx)
    end)
  end

  defp build_vision_item(row, dataset_name, decode_images, config, idx) do
    image_value = parse_image(row["image"] || row[:image], decode_images)
    label = row["label"] || row[:label]

    item = %{
      id: "#{dataset_name}_#{idx}",
      input: %{image: image_value},
      expected: label,
      metadata: %{dataset: to_string(dataset_name)}
    }

    maybe_add_species(item, row, config)
  end

  defp maybe_add_species(item, _row, %{has_species: false}), do: item

  defp maybe_add_species(item, row, %{has_species: true}) do
    species = row["species"] || row[:species]
    if is_nil(species), do: item, else: put_in(item, [:metadata, :species], species)
  end

  defp parse_image(nil, _decode_images), do: %{"bytes" => nil, "path" => nil}

  defp parse_image(value, false) do
    normalize_image(value)
  end

  defp parse_image(value, true) do
    normalized = normalize_image(value)

    case normalized do
      %{"bytes" => bytes} when is_binary(bytes) ->
        case ImageDecoder.decode(bytes) do
          {:ok, image} -> image
          {:error, _} -> normalized
        end

      %{"path" => path} when is_binary(path) ->
        case ImageDecoder.decode_file(path) do
          {:ok, image} -> image
          {:error, _} -> normalized
        end

      _ ->
        normalized
    end
  end

  defp normalize_image(%{"bytes" => _} = value), do: value
  defp normalize_image(%{"path" => _} = value), do: value

  defp normalize_image(value) when is_binary(value) do
    %{"bytes" => value, "path" => nil}
  end

  defp normalize_image(value), do: %{"bytes" => value, "path" => nil}

  defp build_features(config, decode_images) do
    base = %{
      "id" => Value.string(),
      "input" => {:dict, %{"image" => Image.new(decode: decode_images)}},
      "expected" => ClassLabel.new(num_classes: config.num_classes),
      "metadata" => {:dict, %{"dataset" => Value.string()}}
    }

    schema =
      if config.has_species do
        Map.update!(base, "metadata", fn {:dict, inner} ->
          {:dict, Map.put(inner, "species", ClassLabel.new(names: ["cat", "dog"]))}
        end)
      else
        base
      end

    Features.new(schema)
  end
end
