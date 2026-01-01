defmodule HfDatasetsEx.Index.BruteForceTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Index.BruteForce

  describe "new/2" do
    test "creates index with default options" do
      index = BruteForce.new("embeddings")

      assert index.column == "embeddings"
      assert index.metric == :cosine
      assert index.vectors == nil
    end

    test "respects metric option" do
      index = BruteForce.new("embeddings", metric: :l2)

      assert index.metric == :l2
    end
  end

  describe "add/2" do
    test "adds vectors to empty index" do
      index = BruteForce.new("embeddings")
      vectors = Nx.tensor([[1.0, 0.0], [0.0, 1.0]])

      index = BruteForce.add(index, vectors)

      assert index.vectors != nil
      assert Nx.shape(index.vectors) == {2, 2}
    end

    test "appends vectors to existing index" do
      index = BruteForce.new("embeddings")
      v1 = Nx.tensor([[1.0, 0.0]])
      v2 = Nx.tensor([[0.0, 1.0]])

      index = index |> BruteForce.add(v1) |> BruteForce.add(v2)

      assert Nx.shape(index.vectors) == {2, 2}
    end
  end

  describe "search/3" do
    test "returns empty for empty index" do
      index = BruteForce.new("embeddings")
      query = Nx.tensor([1.0, 0.0])

      assert BruteForce.search(index, query, 5) == []
    end

    test "finds nearest neighbors with cosine similarity" do
      vectors =
        Nx.tensor([
          [1.0, 0.0],
          [0.0, 1.0],
          [0.707, 0.707]
        ])

      index =
        BruteForce.new("embeddings", metric: :cosine)
        |> BruteForce.add(vectors)

      query = Nx.tensor([1.0, 0.0])
      results = BruteForce.search(index, query, 3)

      [{_score, first_idx} | _] = results
      assert first_idx == 0
    end

    test "finds nearest neighbors with L2 distance" do
      vectors =
        Nx.tensor([
          [0.0, 0.0],
          [1.0, 1.0],
          [10.0, 10.0]
        ])

      index =
        BruteForce.new("embeddings", metric: :l2)
        |> BruteForce.add(vectors)

      query = Nx.tensor([0.1, 0.1])
      results = BruteForce.search(index, query, 2)

      [{_score, first_idx}, {_score2, second_idx}] = results
      assert first_idx == 0
      assert second_idx == 1
    end

    test "respects k limit" do
      vectors =
        Nx.tensor([
          [1.0, 0.0],
          [0.0, 1.0],
          [1.0, 1.0],
          [0.5, 0.5]
        ])

      index = BruteForce.new("embeddings") |> BruteForce.add(vectors)

      query = Nx.tensor([1.0, 0.0])
      results = BruteForce.search(index, query, 2)

      assert length(results) == 2
    end
  end

  describe "save/2 and load/1" do
    @temp_dir System.tmp_dir!()

    test "round-trip preserves index" do
      vectors = Nx.tensor([[1.0, 0.0], [0.0, 1.0]])

      index =
        BruteForce.new("embeddings", metric: :cosine)
        |> BruteForce.add(vectors)

      path = Path.join(@temp_dir, "test_index_#{:rand.uniform(100_000)}.idx")

      assert :ok = BruteForce.save(index, path)
      assert {:ok, loaded} = BruteForce.load(path)

      assert loaded.column == index.column
      assert loaded.metric == index.metric
      assert Nx.shape(loaded.vectors) == Nx.shape(index.vectors)

      File.rm!(path)
    end
  end
end
