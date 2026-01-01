defmodule HfDatasetsEx.Export.Text do
  @moduledoc """
  Export dataset to plain text file.
  """

  alias HfDatasetsEx.Dataset

  @type options :: [
          column: String.t(),
          append_newline: boolean()
        ]

  @spec write(Dataset.t(), Path.t(), options()) :: :ok | {:error, term()}
  def write(%Dataset{items: items}, path, opts \\ []) do
    column = Keyword.get(opts, :column, "text") |> to_string()
    append_newline = Keyword.get(opts, :append_newline, true)

    with :ok <- ensure_parent_dir(path),
         {:ok, file} <- File.open(path, [:write, :utf8]) do
      try do
        Enum.each(items, &write_item(file, &1, column, append_newline))
        :ok
      rescue
        e -> {:error, e}
      after
        File.close(file)
      end
    end
  end

  defp write_item(file, item, column, append_newline) do
    text = fetch_value(item, column) || ""
    text = if is_binary(text), do: text, else: to_string(text)
    text = if append_newline, do: text <> "\n", else: text
    IO.write(file, text)
  end

  defp ensure_parent_dir(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  defp fetch_value(item, column) do
    case Map.fetch(item, column) do
      {:ok, value} -> value
      :error -> fetch_value_by_string_key(item, to_string(column))
    end
  end

  defp fetch_value_by_string_key(item, column_str) do
    case Enum.find(item, fn {key, _value} -> to_string(key) == column_str end) do
      {_, value} -> value
      nil -> nil
    end
  end
end
