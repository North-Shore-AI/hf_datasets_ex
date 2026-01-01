defmodule HfDatasetsEx.SplitGenerator do
  @moduledoc """
  Defines how to generate a dataset split.

  ## Examples

      # From file path
      SplitGenerator.new(:train, "/path/to/train.jsonl")

      # From generator kwargs
      SplitGenerator.new(:test, %{data_dir: "/data", pattern: "*.json"})

  """

  @type t :: %__MODULE__{
          name: atom(),
          gen_kwargs: map()
        }

  @enforce_keys [:name, :gen_kwargs]
  defstruct [:name, :gen_kwargs]

  @spec new(atom(), map() | Path.t()) :: t()
  def new(split_name, filepath) when is_binary(filepath) do
    %__MODULE__{name: split_name, gen_kwargs: %{filepath: filepath}}
  end

  def new(split_name, gen_kwargs) when is_map(gen_kwargs) do
    %__MODULE__{name: split_name, gen_kwargs: gen_kwargs}
  end
end
