defmodule HfDatasetsEx.Formatter.Elixir do
  @moduledoc """
  Default formatter that returns rows as native Elixir data structures.
  """

  @behaviour HfDatasetsEx.Formatter

  @impl true
  def format_row(row, _opts), do: row

  @impl true
  def format_batch(rows, _opts), do: rows
end
