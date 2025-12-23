# examples/code/deepcoder_example.exs
# Run with: mix run examples/code/deepcoder_example.exs
#
# This example demonstrates loading code generation datasets like DeepCoder.

alias HfDatasetsEx.Loader.Code, as: CodeLoader

IO.puts("=" <> String.duplicate("=", 60))
IO.puts("DeepCoder Code Dataset Example")
IO.puts("=" <> String.duplicate("=", 60))
IO.puts("")

# Load data - DeepCoder requires a config (e.g., primeintellect, taco, lcbv5, codeforces)
IO.puts("Loading DeepCoder dataset (primeintellect config)...")

case CodeLoader.load(:deepcoder, config: "primeintellect", sample_size: 10) do
  {:ok, dataset} ->
    IO.puts("Total problems: #{length(dataset.items)}")
    IO.puts("Available code datasets: #{inspect(CodeLoader.available_datasets())}")
    IO.puts("")

    # Show sample code problems
    IO.puts("-" <> String.duplicate("-", 60))
    IO.puts("Sample Code Problems")
    IO.puts("-" <> String.duplicate("-", 60))
    IO.puts("")

    dataset.items
    |> Enum.take(3)
    |> Enum.each(fn item ->
      IO.puts("ID: #{item.id}")
      IO.puts("Language: #{item.input.language}")
      IO.puts("Problem:")

      problem_preview =
        (item.input.problem || "")
        |> String.slice(0, 200)
        |> String.replace("\n", " ")

      IO.puts("  #{problem_preview}...")
      IO.puts("")

      solution_preview =
        (item.expected || "")
        |> String.slice(0, 200)

      IO.puts("Expected Solution (preview):")
      IO.puts("```#{item.input.language}")
      IO.puts(solution_preview)
      IO.puts("...")
      IO.puts("```")
      IO.puts("")
      IO.puts("-" <> String.duplicate("-", 40))
      IO.puts("")
    end)

  {:error, reason} ->
    IO.puts("Failed to load DeepCoder: #{inspect(reason)}")
    IO.puts("")
    IO.puts("Note: DeepCoder requires a config parameter.")
    IO.puts("Available configs: primeintellect, taco, lcbv5, codeforces")
    IO.puts("")
    IO.puts("Example usage:")
    IO.puts("  CodeLoader.load(:deepcoder, config: \"primeintellect\")")
end

IO.puts("=" <> String.duplicate("=", 60))
IO.puts("Example complete!")
IO.puts("=" <> String.duplicate("=", 60))
