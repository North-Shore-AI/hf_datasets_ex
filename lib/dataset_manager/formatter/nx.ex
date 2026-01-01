defmodule HfDatasetsEx.Formatter.Nx do
  @moduledoc """
  Formatter that converts numeric data to Nx tensors.
  """

  @behaviour HfDatasetsEx.Formatter

  @type_map %{
    int8: {:s, 8},
    int16: {:s, 16},
    int32: {:s, 32},
    int64: {:s, 64},
    uint8: {:u, 8},
    uint16: {:u, 16},
    uint32: {:u, 32},
    uint64: {:u, 64},
    float16: {:f, 16},
    float32: {:f, 32},
    float64: {:f, 64},
    bool: {:u, 8}
  }

  @impl true
  @spec format_row(map(), keyword()) :: map()
  def format_row(row, opts \\ []) do
    columns = Keyword.get(opts, :columns)
    dtype = Keyword.get(opts, :dtype)

    row
    |> maybe_select_columns(columns)
    |> Enum.map(fn {key, value} ->
      {key, to_tensor(value, dtype)}
    end)
    |> Map.new()
  end

  @impl true
  @spec format_batch([map()], keyword()) :: map()
  def format_batch(rows, opts \\ [])

  def format_batch(rows, opts) when rows != [] do
    columns = Keyword.get(opts, :columns)
    dtype = Keyword.get(opts, :dtype)

    keys = rows |> hd() |> Map.keys()
    keys = if columns, do: Enum.filter(keys, &(&1 in columns)), else: keys

    Map.new(keys, fn key ->
      values = Enum.map(rows, &Map.get(&1, key))
      {key, stack_to_tensor(values, dtype)}
    end)
  end

  def format_batch([], _opts), do: %{}

  @doc """
  Convert Features dtype to Nx type.
  """
  @spec dtype_to_nx(atom()) :: Nx.Type.t()
  def dtype_to_nx(dtype) do
    Map.get(@type_map, dtype, {:f, 32})
  end

  defp maybe_select_columns(row, nil), do: row

  defp maybe_select_columns(row, columns) do
    Map.take(row, columns)
  end

  defp to_tensor(value, dtype) when is_number(value) do
    opts = if dtype, do: [type: dtype_to_nx(dtype)], else: []
    Nx.tensor(value, opts)
  end

  defp to_tensor(value, dtype) when is_list(value) do
    if all_numeric?(value) do
      opts = if dtype, do: [type: dtype_to_nx(dtype)], else: []
      Nx.tensor(value, opts)
    else
      value
    end
  end

  defp to_tensor(value, _dtype), do: value

  defp stack_to_tensor(values, dtype) do
    cond do
      Enum.all?(values, &is_number/1) ->
        opts = if dtype, do: [type: dtype_to_nx(dtype)], else: []
        Nx.tensor(values, opts)

      Enum.all?(values, &is_list/1) and Enum.all?(values, &all_numeric?/1) ->
        opts = if dtype, do: [type: dtype_to_nx(dtype)], else: []
        Nx.stack(Enum.map(values, &Nx.tensor(&1, opts)))

      true ->
        values
    end
  end

  defp all_numeric?([]), do: true
  defp all_numeric?([h | t]) when is_number(h), do: all_numeric?(t)
  defp all_numeric?([h | t]) when is_list(h), do: all_numeric?(h) and all_numeric?(t)
  defp all_numeric?(_), do: false
end
