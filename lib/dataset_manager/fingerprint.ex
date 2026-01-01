defmodule HfDatasetsEx.Fingerprint do
  @moduledoc """
  Generates fingerprints for caching dataset transformations.

  A fingerprint is a SHA256 hash that uniquely identifies:
  - The input data
  - The operation being performed
  - The operation arguments

  This enables automatic cache invalidation when inputs or operations change.
  """

  @type t :: String.t()

  @doc """
  Generate a fingerprint for an operation with arguments.

  ## Examples

      fp = Fingerprint.generate(:map, [&String.upcase/1], batched: true)

  """
  @spec generate(atom(), list(), keyword()) :: t()
  def generate(operation, args, opts \\ []) do
    data = %{
      operation: operation,
      args: normalize_args(args),
      opts: normalize_opts(opts),
      lib_version: Application.spec(:hf_datasets_ex, :vsn) |> to_string()
    }

    data
    |> :erlang.term_to_binary()
    |> hash()
  end

  @doc """
  Generate a fingerprint for a dataset's content.

  For efficiency, samples the dataset rather than hashing all items.
  """
  @spec from_dataset(HfDatasetsEx.Dataset.t()) :: t()
  def from_dataset(%{items: items}) do
    data = %{
      count: length(items),
      sample: sample_items(items, 10)
    }

    data
    |> :erlang.term_to_binary()
    |> hash()
  end

  @doc """
  Combine two fingerprints (for chained operations).

  Order matters: combine(a, b) != combine(b, a)
  """
  @spec combine(t(), t()) :: t()
  def combine(fp1, fp2) do
    hash(fp1 <> fp2)
  end

  @doc """
  Combine multiple fingerprints in order.
  """
  @spec combine_all([t()]) :: t()
  def combine_all([]), do: generate(:empty, [])
  def combine_all([fp]), do: fp

  def combine_all([fp1, fp2 | rest]) do
    combine_all([combine(fp1, fp2) | rest])
  end

  defp hash(data) when is_binary(data) do
    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
  end

  defp normalize_args(args) do
    Enum.map(args, fn
      f when is_function(f) ->
        info = :erlang.fun_info(f)
        %{type: :function, module: info[:module], name: info[:name], arity: info[:arity]}

      other ->
        other
    end)
  end

  defp normalize_opts(opts) do
    opts
    |> Keyword.drop([:new_fingerprint, :cache_file])
    |> Enum.sort()
  end

  defp sample_items(items, n) when length(items) <= n * 2 do
    items
  end

  defp sample_items(items, n) do
    first = Enum.take(items, n)
    last = items |> Enum.reverse() |> Enum.take(n) |> Enum.reverse()
    first ++ last
  end
end
