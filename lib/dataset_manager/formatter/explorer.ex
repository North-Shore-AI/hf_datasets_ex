defmodule HfDatasetsEx.Formatter.Explorer do
  @moduledoc """
  Formatter that converts dataset rows to Explorer DataFrames.
  """

  @behaviour HfDatasetsEx.Formatter

  @impl true
  def format_batch(rows, opts \\ []) do
    columns = Keyword.get(opts, :columns)
    df = Explorer.DataFrame.new(rows)

    if columns do
      Explorer.DataFrame.select(df, columns)
    else
      df
    end
  end

  @impl true
  def format_row(row, _opts), do: row
end
