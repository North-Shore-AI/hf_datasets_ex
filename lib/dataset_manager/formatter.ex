defmodule HfDatasetsEx.Formatter do
  @moduledoc """
  Behaviour for dataset output formatters.
  """

  @type format_type :: :elixir | :nx | :explorer | :custom

  @callback format_row(map(), keyword()) :: any()
  @callback format_batch([map()], keyword()) :: any()

  @optional_callbacks [format_batch: 2]

  @spec get(format_type()) :: module()
  def get(:elixir), do: HfDatasetsEx.Formatter.Elixir
  def get(:nx), do: HfDatasetsEx.Formatter.Nx
  def get(:explorer), do: HfDatasetsEx.Formatter.Explorer
  def get(:custom), do: HfDatasetsEx.Formatter.Custom
  def get(other), do: raise(ArgumentError, "Unknown format: #{inspect(other)}")
end
