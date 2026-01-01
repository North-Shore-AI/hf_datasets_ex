# Vector Similarity Search Example
# Demonstrates built-in vector search for embeddings

alias HfDatasetsEx.Dataset

IO.puts("=== Vector Similarity Search Example ===\n")

# Create dataset with embedding vectors (simulating document embeddings)
# In real use, these would come from an embedding model
dataset =
  Dataset.from_list([
    %{"id" => 1, "text" => "The cat sat on the mat", "embedding" => [0.9, 0.1, 0.0]},
    %{"id" => 2, "text" => "Dogs are loyal pets", "embedding" => [0.1, 0.9, 0.1]},
    %{"id" => 3, "text" => "The kitten played with yarn", "embedding" => [0.85, 0.15, 0.05]},
    %{"id" => 4, "text" => "Fish swim in the ocean", "embedding" => [0.0, 0.1, 0.95]},
    %{"id" => 5, "text" => "Cats love to sleep", "embedding" => [0.88, 0.12, 0.02]},
    %{"id" => 6, "text" => "Puppies are playful", "embedding" => [0.15, 0.85, 0.08]}
  ])

IO.puts("Created dataset with #{Dataset.num_items(dataset)} documents\n")

# Add a search index on the embedding column
IO.puts("=== Creating Search Index ===")
indexed = Dataset.add_index(dataset, "embedding", metric: :cosine)
IO.puts("Added cosine similarity index on 'embedding' column\n")

# Search for documents similar to "cat-like" query
IO.puts("=== Searching for Cat-like Documents ===")
# Similar to cat embeddings
cat_query = Nx.tensor([0.9, 0.1, 0.0])
{scores, examples} = Dataset.get_nearest_examples(indexed, "embedding", cat_query, k: 3)

IO.puts("Query: cat-like vector [0.9, 0.1, 0.0]")
IO.puts("Top 3 results:")

Enum.zip(scores, examples)
|> Enum.with_index(1)
|> Enum.each(fn {{score, example}, rank} ->
  IO.puts("  #{rank}. (score: #{Float.round(score, 4)}) #{example["text"]}")
end)

# Search for dog-like documents
IO.puts("\n=== Searching for Dog-like Documents ===")
dog_query = Nx.tensor([0.1, 0.9, 0.1])
{scores, examples} = Dataset.get_nearest_examples(indexed, "embedding", dog_query, k: 2)

IO.puts("Query: dog-like vector [0.1, 0.9, 0.1]")
IO.puts("Top 2 results:")

Enum.zip(scores, examples)
|> Enum.with_index(1)
|> Enum.each(fn {{score, example}, rank} ->
  IO.puts("  #{rank}. (score: #{Float.round(score, 4)}) #{example["text"]}")
end)

# Save and load index
IO.puts("\n=== Index Persistence ===")
tmp_path = Path.join(System.tmp_dir!(), "search_index_#{:rand.uniform(100_000)}.idx")
:ok = Dataset.save_index(indexed, "embedding", tmp_path)
IO.puts("Saved index to: #{tmp_path}")
IO.puts("Index file size: #{File.stat!(tmp_path).size} bytes")

# Load into a fresh dataset
fresh_dataset =
  Dataset.from_list([
    %{"id" => 1, "text" => "The cat sat on the mat", "embedding" => [0.9, 0.1, 0.0]},
    %{"id" => 2, "text" => "Dogs are loyal pets", "embedding" => [0.1, 0.9, 0.1]}
  ])

{:ok, reloaded} = Dataset.load_index(fresh_dataset, "embedding", tmp_path)
IO.puts("Loaded index into fresh dataset")

# Cleanup
File.rm!(tmp_path)

# Different metrics
IO.puts("\n=== Different Distance Metrics ===")
l2_indexed = Dataset.add_index(dataset, "embedding", metric: :l2)
{l2_scores, _} = Dataset.get_nearest_examples(l2_indexed, "embedding", cat_query, k: 2)
IO.puts("L2 distance scores: #{inspect(Enum.map(l2_scores, &Float.round(&1, 4)))}")

IO.puts("\n=== Vector Search Example Complete ===")
