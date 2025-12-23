defmodule HfDatasetsEx.Format.JSON do
  @moduledoc """
  JSON format parser.

  Parses JSON files containing either an array of objects or a single object.

  ## Example

      # Array of objects
      {:ok, items} = JSON.parse("data.json")
      # => [%{"id" => 1, ...}, %{"id" => 2, ...}]

      # Single object (wrapped in list)
      {:ok, items} = JSON.parse("config.json")
      # => [%{"key" => "value"}]

  """

  @behaviour HfDatasetsEx.Format

  @impl true
  def parse(path) do
    with {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content) do
      items = if is_list(data), do: data, else: [data]
      {:ok, items}
    end
  rescue
    e -> {:error, {:parse_error, e}}
  end

  @impl true
  def parse_stream(_stream) do
    # JSON doesn't support streaming - must read entire file
    raise "JSON format does not support streaming. Use parse/1 instead."
  end

  @impl true
  def handles?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext == ".json"
  end
end
