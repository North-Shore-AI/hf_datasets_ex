defmodule HfDatasetsEx.BuilderConfig do
  @moduledoc """
  Configuration for a dataset builder variant.

  ## Examples

      config = BuilderConfig.new(
        name: "stem",
        version: "1.0.0",
        description: "STEM subjects only"
      )

  """

  @type t :: %__MODULE__{
          name: String.t(),
          version: String.t(),
          description: String.t() | nil,
          data_dir: Path.t() | nil,
          data_files: map() | nil
        }

  @enforce_keys [:name]
  defstruct [
    :name,
    version: "1.0.0",
    description: nil,
    data_dir: nil,
    data_files: nil
  ]

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      name: Keyword.get(opts, :name, "default"),
      version: Keyword.get(opts, :version, "1.0.0"),
      description: Keyword.get(opts, :description),
      data_dir: Keyword.get(opts, :data_dir),
      data_files: Keyword.get(opts, :data_files)
    }
  end
end
