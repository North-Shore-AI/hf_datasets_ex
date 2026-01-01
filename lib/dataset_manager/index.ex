defmodule HfDatasetsEx.Index do
  @moduledoc """
  Behaviour for search indices.
  """

  @type t :: struct()
  @type search_result :: {float(), non_neg_integer()}

  @callback new(String.t(), keyword()) :: t()
  @callback add(t(), Nx.Tensor.t()) :: t()
  @callback search(t(), Nx.Tensor.t(), non_neg_integer()) :: [search_result()]
  @callback save(t(), Path.t()) :: :ok | {:error, term()}
  @callback load(Path.t()) :: {:ok, t()} | {:error, term()}

  @optional_callbacks [save: 2, load: 1]
end
