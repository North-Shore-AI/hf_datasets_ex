# Export Formats Example
# Demonstrates exporting datasets to various file formats

alias HfDatasetsEx.Dataset

IO.puts("=== Export Formats Example ===\n")

# Create a real dataset
dataset =
  Dataset.from_list([
    %{"name" => "Alice", "age" => 30, "score" => 95.5},
    %{"name" => "Bob", "age" => 25, "score" => 87.2},
    %{"name" => "Charlie", "age" => 35, "score" => 91.8}
  ])

IO.puts("Created dataset with #{Dataset.num_items(dataset)} items")

# Create temp directory for outputs
tmp_dir = Path.join(System.tmp_dir!(), "hf_datasets_export_#{:rand.uniform(100_000)}")
File.mkdir_p!(tmp_dir)
IO.puts("Output directory: #{tmp_dir}\n")

# Export to CSV
csv_path = Path.join(tmp_dir, "data.csv")
:ok = Dataset.to_csv(dataset, csv_path)
IO.puts("Exported to CSV: #{csv_path}")
IO.puts("CSV content:\n#{File.read!(csv_path)}")

# Export to JSON (records format)
json_path = Path.join(tmp_dir, "data.json")
:ok = Dataset.to_json(dataset, json_path, pretty: true)
IO.puts("\nExported to JSON: #{json_path}")
IO.puts("JSON content:\n#{File.read!(json_path)}")

# Export to JSONL
jsonl_path = Path.join(tmp_dir, "data.jsonl")
:ok = Dataset.to_jsonl(dataset, jsonl_path)
IO.puts("\nExported to JSONL: #{jsonl_path}")
IO.puts("JSONL content:\n#{File.read!(jsonl_path)}")

# Export to Parquet
parquet_path = Path.join(tmp_dir, "data.parquet")
:ok = Dataset.to_parquet(dataset, parquet_path)
IO.puts("\nExported to Parquet: #{parquet_path}")
IO.puts("Parquet file size: #{File.stat!(parquet_path).size} bytes")

# Export to Arrow IPC
arrow_path = Path.join(tmp_dir, "data.arrow")
:ok = Dataset.to_arrow(dataset, arrow_path)
IO.puts("\nExported to Arrow: #{arrow_path}")
IO.puts("Arrow file size: #{File.stat!(arrow_path).size} bytes")

# Export to plain text (uses specific column)
text_path = Path.join(tmp_dir, "names.txt")
:ok = Dataset.to_text(dataset, text_path, column: "name")
IO.puts("\nExported to Text: #{text_path}")
IO.puts("Text content:\n#{File.read!(text_path)}")

# Round-trip verification
IO.puts("\n=== Round-trip Verification ===")

{:ok, csv_loaded} = Dataset.from_csv(csv_path)
IO.puts("CSV round-trip: #{Dataset.num_items(csv_loaded)} items loaded")

{:ok, json_loaded} = Dataset.from_json(jsonl_path)
IO.puts("JSONL round-trip: #{Dataset.num_items(json_loaded)} items loaded")

{:ok, parquet_loaded} = Dataset.from_parquet(parquet_path)
IO.puts("Parquet round-trip: #{Dataset.num_items(parquet_loaded)} items loaded")

# Cleanup
File.rm_rf!(tmp_dir)
IO.puts("\nCleaned up temp directory")
IO.puts("\n=== Export Formats Example Complete ===")
