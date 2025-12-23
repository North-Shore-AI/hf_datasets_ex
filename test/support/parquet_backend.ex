defmodule TestSupport.ParquetBackend do
  @moduledoc false

  def from_parquet(path, opts \\ []) do
    send(self(), {:from_parquet, path, opts})
    Explorer.DataFrame.from_parquet(path, opts)
  end

  def to_rows(df), do: Explorer.DataFrame.to_rows(df)
  def n_rows(df), do: Explorer.DataFrame.n_rows(df)
  def slice(df, offset, length), do: Explorer.DataFrame.slice(df, offset, length)
end
