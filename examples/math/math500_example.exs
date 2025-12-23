# examples/math/math500_example.exs
# Run with: mix run examples/math/math500_example.exs
#
# This example demonstrates loading the MATH-500 dataset.

alias HfDatasetsEx.Loader.Math

IO.puts("=" <> String.duplicate("=", 60))
IO.puts("MATH-500 Dataset Example")
IO.puts("=" <> String.duplicate("=", 60))
IO.puts("")

# Load MATH-500
IO.puts("Loading MATH-500 dataset...")
{:ok, dataset} = Math.load(:math_500, sample_size: 10)

IO.puts("Total items: #{length(dataset.items)}")
IO.puts("")

# Show sample problems
IO.puts("-" <> String.duplicate("-", 60))
IO.puts("Sample Problems")
IO.puts("-" <> String.duplicate("-", 60))
IO.puts("")

dataset.items
|> Enum.take(3)
|> Enum.each(fn item ->
  IO.puts("ID: #{item.id}")
  IO.puts("Problem: #{item.input.problem}")
  IO.puts("Answer: #{item.expected}")
  IO.puts("Type: #{item.metadata.type}")
  IO.puts("Level: #{item.metadata.level}")
  IO.puts("")
end)

# Test boxed answer extraction
IO.puts("-" <> String.duplicate("-", 60))
IO.puts("Boxed Answer Extraction Demo")
IO.puts("-" <> String.duplicate("-", 60))
IO.puts("")

test_cases = [
  "The answer is \\boxed{42}",
  "Therefore, $x = \\boxed{\\frac{1}{2}}$",
  "\\boxed{x^2 + 2x + 1}"
]

Enum.each(test_cases, fn text ->
  extracted = Math.extract_boxed_answer(text)
  IO.puts("Input: #{String.slice(text, 0, 50)}")
  IO.puts("Extracted: #{extracted}")
  IO.puts("")
end)

IO.puts("=" <> String.duplicate("=", 60))
IO.puts("Example complete!")
IO.puts("=" <> String.duplicate("=", 60))
