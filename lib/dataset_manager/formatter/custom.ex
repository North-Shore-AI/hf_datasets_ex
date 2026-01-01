defmodule HfDatasetsEx.Formatter.Custom do
  @moduledoc """
  Formatter that applies a custom transform function to dataset rows.
  """

  @behaviour HfDatasetsEx.Formatter

  @type transform_fn :: (map() -> any())

  @impl true
  def format_row(row, opts) do
    transform = Keyword.fetch!(opts, :transform)
    transform.(row)
  end

  @impl true
  def format_batch(rows, opts) do
    transform = Keyword.fetch!(opts, :transform)

    case Keyword.get(opts, :batched, false) do
      true -> transform.(rows)
      false -> Enum.map(rows, transform)
    end
  end
end
