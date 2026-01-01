defmodule HfDatasetsEx.DatasetInfo do
  @moduledoc """
  Metadata about a dataset.
  """

  alias HfDatasetsEx.Features

  @type t :: %__MODULE__{
          description: String.t() | nil,
          citation: String.t() | nil,
          homepage: String.t() | nil,
          license: String.t() | nil,
          features: Features.t() | nil,
          supervised_keys: {String.t(), String.t()} | nil,
          builder_name: String.t() | nil,
          config_name: String.t() | nil,
          version: String.t() | nil,
          splits: map() | nil,
          download_size: non_neg_integer() | nil,
          dataset_size: non_neg_integer() | nil
        }

  defstruct [
    :description,
    :citation,
    :homepage,
    :license,
    :features,
    :supervised_keys,
    :builder_name,
    :config_name,
    :version,
    :splits,
    :download_size,
    :dataset_size
  ]

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end
end
