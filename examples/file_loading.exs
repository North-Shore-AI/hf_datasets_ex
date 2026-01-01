# File Loading Example
# Demonstrates loading datasets from various file formats

alias HfDatasetsEx.Dataset

IO.puts("=== File Loading Example ===\n")

# Create temp directory
tmp_dir = Path.join(System.tmp_dir!(), "hf_datasets_load_#{:rand.uniform(100_000)}")
File.mkdir_p!(tmp_dir)
IO.puts("Working directory: #{tmp_dir}\n")

# Create test files
IO.puts("=== Creating Test Files ===")

# CSV file
csv_content = """
name,age,city
Alice,30,NYC
Bob,25,LA
Charlie,35,Chicago
"""

csv_path = Path.join(tmp_dir, "people.csv")
File.write!(csv_path, csv_content)
IO.puts("Created: #{csv_path}")

# JSON file
json_content = """
[
  {"product": "Widget", "price": 9.99, "stock": 100},
  {"product": "Gadget", "price": 19.99, "stock": 50}
]
"""

json_path = Path.join(tmp_dir, "products.json")
File.write!(json_path, json_content)
IO.puts("Created: #{json_path}")

# JSONL file
jsonl_content = """
{"question": "What is 2+2?", "answer": "4"}
{"question": "What is the capital of France?", "answer": "Paris"}
{"question": "Who wrote Hamlet?", "answer": "Shakespeare"}
"""

jsonl_path = Path.join(tmp_dir, "qa.jsonl")
File.write!(jsonl_path, jsonl_content)
IO.puts("Created: #{jsonl_path}")

# Text file (one line per example)
text_content = """
The quick brown fox jumps over the lazy dog.
Pack my box with five dozen liquor jugs.
How vexingly quick daft zebras jump!
"""

text_path = Path.join(tmp_dir, "sentences.txt")
File.write!(text_path, text_content)
IO.puts("Created: #{text_path}")

# Load from CSV
IO.puts("\n=== Loading from CSV ===")
{:ok, csv_ds} = Dataset.from_csv(csv_path)
IO.puts("Loaded #{Dataset.num_items(csv_ds)} items from CSV")
IO.puts("Columns: #{inspect(Dataset.column_names(csv_ds))}")
IO.puts("First item: #{inspect(hd(csv_ds.items))}")

# Load from JSON
IO.puts("\n=== Loading from JSON ===")
{:ok, json_ds} = Dataset.from_json(json_path)
IO.puts("Loaded #{Dataset.num_items(json_ds)} items from JSON")
IO.puts("Columns: #{inspect(Dataset.column_names(json_ds))}")

# Load from JSONL
IO.puts("\n=== Loading from JSONL ===")
# Auto-detects JSONL
{:ok, jsonl_ds} = Dataset.from_json(jsonl_path)
IO.puts("Loaded #{Dataset.num_items(jsonl_ds)} items from JSONL")
IO.puts("First Q: #{hd(jsonl_ds.items)["question"]}")

# Load from text
IO.puts("\n=== Loading from Text ===")
{:ok, text_ds} = Dataset.from_text(text_path)
IO.puts("Loaded #{Dataset.num_items(text_ds)} items from text file")
IO.puts("Column name: #{inspect(Dataset.column_names(text_ds))}")
IO.puts("First line: #{hd(text_ds.items)["text"]}")

# Custom column name for text
{:ok, text_ds2} = Dataset.from_text(text_path, column: "sentence")
IO.puts("With custom column: #{inspect(Dataset.column_names(text_ds2))}")

# Create Parquet file and load it
IO.puts("\n=== Loading from Parquet ===")
parquet_path = Path.join(tmp_dir, "data.parquet")

sample =
  Dataset.from_list([
    %{"id" => 1, "value" => 100},
    %{"id" => 2, "value" => 200}
  ])

:ok = Dataset.to_parquet(sample, parquet_path)
{:ok, parquet_ds} = Dataset.from_parquet(parquet_path)
IO.puts("Loaded #{Dataset.num_items(parquet_ds)} items from Parquet")

# Select specific columns from Parquet
{:ok, parquet_ds2} = Dataset.from_parquet(parquet_path, columns: ["value"])
IO.puts("With column selection: #{inspect(Dataset.column_names(parquet_ds2))}")

# Using from_generator
IO.puts("\n=== Loading from Generator ===")

lazy_ds =
  Dataset.from_generator(fn ->
    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn n -> %{"n" => n, "square" => n * n} end)
    |> Stream.take(5)
  end)

IO.puts("Created lazy IterableDataset")
IO.puts("Taking 3 items: #{inspect(Enum.take(lazy_ds, 3))}")

# Eager generator
eager_ds =
  Dataset.from_generator(
    fn -> 1..5 |> Stream.map(fn n -> %{"x" => n} end) end,
    eager: true
  )

IO.puts("\nEager Dataset: #{Dataset.num_items(eager_ds)} items")

# Bang versions (raise on error)
IO.puts("\n=== Bang Versions ===")
csv_ds! = Dataset.from_csv!(csv_path)
IO.puts("from_csv! loaded #{Dataset.num_items(csv_ds!)} items")

# Cleanup
File.rm_rf!(tmp_dir)
IO.puts("\nCleaned up temp directory")

IO.puts("\n=== File Loading Example Complete ===")
