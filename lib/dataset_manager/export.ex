defmodule HfDatasetsEx.Export do
  @moduledoc """
  Export functionality for datasets.
  """

  alias HfDatasetsEx.Dataset

  @doc """
  Export dataset to CSV file.
  """
  @spec to_csv(Dataset.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def to_csv(%Dataset{} = dataset, path, opts \\ []) do
    delimiter = opts |> Keyword.get(:delimiter, ",") |> to_string()
    include_headers = Keyword.get(opts, :headers, true)
    columns = Keyword.get(opts, :columns) || Dataset.column_names(dataset)

    with :ok <- ensure_parent_dir(path),
         {:ok, file} <- File.open(path, [:write, :utf8]) do
      try do
        if include_headers, do: write_csv_header(file, columns, delimiter)
        Enum.each(dataset.items, &write_csv_row(file, &1, columns, delimiter))
        :ok
      after
        File.close(file)
      end
    end
  end

  defp write_csv_header(file, columns, delimiter) do
    header = Enum.map_join(columns, delimiter, &to_string/1)
    IO.write(file, header <> "\n")
  end

  defp write_csv_row(file, item, columns, delimiter) do
    row = Enum.map_join(columns, delimiter, &format_csv_column(item, &1, delimiter))
    IO.write(file, row <> "\n")
  end

  defp format_csv_column(item, col, delimiter) do
    item
    |> fetch_value(col)
    |> normalize_csv_value()
    |> escape_csv_value(delimiter)
  end

  @doc """
  Export dataset to JSON file.
  """
  @spec to_json(Dataset.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def to_json(%Dataset{items: items}, path, opts \\ []) do
    orient = Keyword.get(opts, :orient, :records)
    pretty = Keyword.get(opts, :pretty, false)
    json_opts = if pretty, do: [pretty: true], else: []

    with :ok <- ensure_parent_dir(path),
         {:ok, content} <- json_content(items, orient) do
      File.write(path, Jason.encode!(content, json_opts))
    end
  end

  @doc """
  Export dataset to JSONL file.
  """
  @spec to_jsonl(Dataset.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def to_jsonl(%Dataset{items: items}, path, _opts \\ []) do
    with :ok <- ensure_parent_dir(path),
         {:ok, file} <- File.open(path, [:write, :utf8]) do
      try do
        Enum.each(items, fn item ->
          item
          |> normalize_json()
          |> Jason.encode!()
          |> then(&IO.write(file, &1 <> "\n"))
        end)

        :ok
      after
        File.close(file)
      end
    end
  end

  @doc """
  Export dataset to Parquet file.
  """
  @spec to_parquet(Dataset.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def to_parquet(%Dataset{items: items}, path, opts \\ []) do
    compression =
      opts
      |> Keyword.get(:compression, :snappy)
      |> normalize_parquet_compression()

    with :ok <- ensure_parent_dir(path) do
      df = Explorer.DataFrame.new(items)
      Explorer.DataFrame.to_parquet(df, path, compression: compression)
    end
  end

  defp ensure_parent_dir(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  defp json_content(items, :records) do
    {:ok, Enum.map(items, &normalize_json/1)}
  end

  defp json_content(items, :columns) do
    items =
      items
      |> Enum.map(&normalize_json/1)
      |> to_column_format()

    {:ok, items}
  end

  defp json_content(_items, orient), do: {:error, {:invalid_orient, orient}}

  defp to_column_format([]), do: %{}

  defp to_column_format([first | _] = items) do
    keys = Map.keys(first)

    Map.new(keys, fn key ->
      {key, Enum.map(items, &Map.get(&1, key))}
    end)
  end

  defp fetch_value(item, column) do
    case Map.fetch(item, column) do
      {:ok, value} -> value
      :error -> fetch_value_by_string_key(item, to_string(column))
    end
  end

  defp fetch_value_by_string_key(item, column_key) do
    case Enum.find(item, fn {key, _value} -> to_string(key) == column_key end) do
      {_, value} -> value
      nil -> nil
    end
  end

  defp normalize_csv_value(nil), do: ""
  defp normalize_csv_value(value) when is_binary(value), do: normalize_binary(value)
  defp normalize_csv_value(%_{} = value), do: inspect(value)

  defp normalize_csv_value(value) when is_map(value) or is_list(value) do
    value
    |> normalize_json()
    |> Jason.encode!()
  end

  defp normalize_csv_value(value), do: to_string(value)

  defp escape_csv_value(value, delimiter) when is_binary(value) do
    needs_quoting = String.contains?(value, [delimiter, "\"", "\n", "\r"])

    if needs_quoting do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end

  defp normalize_json(value) when is_binary(value), do: normalize_binary(value)

  defp normalize_json(%_{} = value) do
    case Jason.Encoder.impl_for(value) do
      Jason.Encoder.Any -> inspect(value)
      _ -> value
    end
  end

  defp normalize_json(value) when is_map(value) do
    Map.new(value, fn {key, value} -> {key, normalize_json(value)} end)
  end

  defp normalize_json(value) when is_list(value) do
    Enum.map(value, &normalize_json/1)
  end

  defp normalize_json(value), do: value

  defp normalize_binary(value) do
    if String.valid?(value) do
      value
    else
      "base64:" <> Base.encode64(value)
    end
  end

  defp normalize_parquet_compression(:none), do: nil
  defp normalize_parquet_compression(value), do: value
end
