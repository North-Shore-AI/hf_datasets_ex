defmodule HfDatasetsEx.Format.Text do
  @moduledoc """
  Parser for plain text files.

  Each line becomes a row with a single "text" column.
  """

  @behaviour HfDatasetsEx.Format

  @type options :: [
          column: String.t(),
          strip: boolean(),
          skip_empty: boolean()
        ]

  @impl true
  @spec parse(Path.t(), options()) :: {:ok, [map()]} | {:error, term()}
  def parse(path, opts \\ []) do
    items =
      path
      |> parse_stream(opts)
      |> Enum.to_list()

    {:ok, items}
  rescue
    e -> {:error, e}
  end

  def parse_stream(path_or_stream), do: parse_stream(path_or_stream, [])

  @impl true
  @spec parse_stream(Path.t(), options()) :: Enumerable.t()
  def parse_stream(path, opts) when is_binary(path) do
    column = Keyword.get(opts, :column, "text") |> to_string()
    strip = Keyword.get(opts, :strip, true)
    skip_empty = Keyword.get(opts, :skip_empty, true)

    path
    |> File.stream!([:utf8])
    |> build_stream(column, strip, skip_empty)
  end

  def parse_stream(stream, opts) do
    column = Keyword.get(opts, :column, "text") |> to_string()
    strip = Keyword.get(opts, :strip, true)
    skip_empty = Keyword.get(opts, :skip_empty, true)

    build_stream(stream, column, strip, skip_empty)
  end

  @impl true
  def handles?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext in [".txt", ".text"]
  end

  defp build_stream(stream, column, strip, skip_empty) do
    stream
    |> Stream.map(fn line ->
      if strip do
        String.trim(line)
      else
        String.trim_trailing(line, "\n")
      end
    end)
    |> maybe_skip_empty(skip_empty)
    |> Stream.map(fn line -> %{column => line} end)
  end

  defp maybe_skip_empty(stream, true) do
    Stream.reject(stream, &(&1 == ""))
  end

  defp maybe_skip_empty(stream, false), do: stream
end
