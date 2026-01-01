# Nx Tensor Formatting Example
# Demonstrates formatting dataset output as Nx tensors for ML workflows

alias HfDatasetsEx.Dataset

IO.puts("=== Nx Tensor Formatting Example ===\n")

# Create dataset with numeric data
dataset =
  Dataset.from_list([
    %{"x" => 1.0, "y" => 2.0, "label" => 0},
    %{"x" => 3.0, "y" => 4.0, "label" => 1},
    %{"x" => 5.0, "y" => 6.0, "label" => 0},
    %{"x" => 7.0, "y" => 8.0, "label" => 1},
    %{"x" => 9.0, "y" => 10.0, "label" => 0},
    %{"x" => 11.0, "y" => 12.0, "label" => 1}
  ])

IO.puts("Created dataset with #{Dataset.num_items(dataset)} items\n")

# Default format returns Elixir maps
IO.puts("=== Default Elixir Format ===")
[first | _] = Enum.take(dataset, 1)
IO.puts("First item type: #{inspect(first)}")

x_type =
  if is_struct(first["x"], Nx.Tensor), do: "Nx.Tensor", else: "native #{inspect(first["x"])}"

IO.puts("x value type: #{x_type}\n")

# Set format to Nx tensors
IO.puts("=== Nx Tensor Format ===")
nx_dataset = Dataset.set_format(dataset, :nx)

[first_nx | _] = Enum.take(nx_dataset, 1)
IO.puts("First item with Nx format:")
IO.puts("  x: #{inspect(first_nx["x"])} (shape: #{inspect(Nx.shape(first_nx["x"]))})")
IO.puts("  y: #{inspect(first_nx["y"])} (shape: #{inspect(Nx.shape(first_nx["y"]))})")
IO.puts("  label: #{inspect(first_nx["label"])}\n")

# Batch iteration with stacked tensors
IO.puts("=== Batch Iteration ===")
batches = nx_dataset |> Dataset.iter(batch_size: 2) |> Enum.to_list()
IO.puts("Number of batches (batch_size=2): #{length(batches)}")

first_batch = hd(batches)
IO.puts("\nFirst batch tensors:")
IO.puts("  x shape: #{inspect(Nx.shape(first_batch["x"]))}")
IO.puts("  y shape: #{inspect(Nx.shape(first_batch["y"]))}")
IO.puts("  label shape: #{inspect(Nx.shape(first_batch["label"]))}")
IO.puts("  x values: #{inspect(Nx.to_flat_list(first_batch["x"]))}")

# Select specific columns
IO.puts("\n=== Column Selection ===")
selected = Dataset.set_format(dataset, :nx, columns: ["x", "y"])
[row | _] = Enum.take(selected, 1)
IO.puts("Selected columns: #{inspect(Map.keys(row))}")

# with_format returns new dataset without modifying original
IO.puts("\n=== with_format (non-mutating) ===")
original = Dataset.from_list([%{"a" => 1.0}])
formatted = Dataset.with_format(original, :nx)
IO.puts("Original format: #{inspect(original.format)}")
IO.puts("Formatted copy format: #{inspect(formatted.format)}")

# Reset format back to Elixir
IO.puts("\n=== Reset Format ===")
reset = Dataset.reset_format(nx_dataset)
[first_reset | _] = Enum.take(reset, 1)
IO.puts("After reset, x type: #{if is_number(first_reset["x"]), do: "number", else: "tensor"}")

IO.puts("\n=== Nx Formatting Example Complete ===")
