defmodule HfDatasetsEx.Sampler do
  @moduledoc """
  Create representative subsets of datasets for experimentation.

  Supports:
  - Random sampling
  - Stratified sampling (maintain distribution)
  - K-fold cross-validation
  """

  alias HfDatasetsEx.Dataset

  @doc """
  Create random sample from dataset.

  ## Options
    * `:size` - Number of items to sample (default: 100)
    * `:seed` - Random seed for reproducibility (default: random)

  ## Examples

      {:ok, dataset} = HfDatasetsEx.Loader.load(:mmlu)
      {:ok, sample} = HfDatasetsEx.Sampler.random(dataset, size: 200)

      length(sample.items)
      # => 200
  """
  @spec random(Dataset.t(), keyword()) :: {:ok, Dataset.t()}
  def random(%Dataset{} = dataset, opts \\ []) do
    size = Keyword.get(opts, :size, 100)
    seed = Keyword.get(opts, :seed, :rand.uniform(1_000_000))

    :rand.seed(:exsss, {seed, seed, seed})

    sampled_items = Enum.take_random(dataset.items, min(size, length(dataset.items)))

    sampled_dataset = %{
      dataset
      | name: "#{dataset.name}_random_#{size}",
        items: sampled_items,
        metadata:
          Map.merge(dataset.metadata, %{
            sample_method: :random,
            sample_size: length(sampled_items),
            sample_seed: seed,
            original_size: length(dataset.items)
          })
    }

    {:ok, sampled_dataset}
  end

  @doc """
  Create stratified sample maintaining distribution of a field.

  ## Options
    * `:size` - Total number of items to sample (required)
    * `:strata_field` - Field path to stratify by (required)
        Can be atom or list of keys for nested access

  ## Examples

      # Sample 200 items, maintaining subject distribution
      {:ok, sample} = HfDatasetsEx.Sampler.stratified(dataset,
        size: 200,
        strata_field: [:metadata, :subject]
      )

      # If original has 30% science, 40% humanities, 30% other
      # Sample will have same proportions
  """
  @spec stratified(Dataset.t(), keyword()) :: {:ok, Dataset.t()} | {:error, term()}
  def stratified(%Dataset{} = dataset, opts \\ []) do
    with {:ok, size} <- Keyword.fetch(opts, :size),
         {:ok, strata_field} <- Keyword.fetch(opts, :strata_field) do
      # Normalize strata_field to list
      field_path = if is_list(strata_field), do: strata_field, else: [strata_field]

      # Group by strata
      groups = Enum.group_by(dataset.items, &get_in(&1, field_path))

      # Calculate samples per stratum
      total_items = length(dataset.items)

      samples_per_stratum =
        groups
        |> Enum.map(fn {stratum, items} ->
          proportion = length(items) / total_items
          sample_count = round(proportion * size)
          {stratum, sample_count}
        end)
        |> Map.new()

      # Adjust if total exceeds requested size due to rounding
      total_allocated = samples_per_stratum |> Map.values() |> Enum.sum()

      samples_per_stratum =
        if total_allocated > size do
          # Reduce largest strata first to fit within size
          excess = total_allocated - size

          samples_per_stratum
          |> Enum.sort_by(fn {_stratum, count} -> -count end)
          |> Enum.reduce({%{}, excess}, fn {stratum, count}, {acc_map, remaining} ->
            if remaining > 0 do
              reduction = min(remaining, count)
              {Map.put(acc_map, stratum, count - reduction), remaining - reduction}
            else
              {Map.put(acc_map, stratum, count), 0}
            end
          end)
          |> elem(0)
        else
          samples_per_stratum
        end

      # Sample from each stratum
      sampled_items =
        groups
        |> Enum.flat_map(fn {stratum, items} ->
          n = Map.get(samples_per_stratum, stratum, 0)
          Enum.take_random(items, min(n, length(items)))
        end)

      sampled_dataset = %{
        dataset
        | name: "#{dataset.name}_stratified_#{size}",
          items: sampled_items,
          metadata:
            Map.merge(dataset.metadata, %{
              sample_method: :stratified,
              sample_size: length(sampled_items),
              strata_field: field_path,
              strata_distribution: samples_per_stratum,
              original_size: total_items
            })
      }

      {:ok, sampled_dataset}
    else
      :error -> {:error, :missing_required_option}
    end
  end

  @doc """
  Create k-fold cross-validation splits.

  ## Options
    * `:k` - Number of folds (default: 5)
    * `:shuffle` - Shuffle before splitting (default: true)
    * `:seed` - Random seed for shuffling (default: random)

  ## Examples

      {:ok, folds} = HfDatasetsEx.Sampler.k_fold(dataset, k: 5)

      # Returns 5 train/test splits
      Enum.each(folds, fn {train, test} ->
        # Train on 80%, test on 20%
        evaluate_model(train, test)
      end)
  """
  @spec k_fold(Dataset.t(), keyword()) :: {:ok, [{Dataset.t(), Dataset.t()}]}
  def k_fold(%Dataset{} = dataset, opts \\ []) do
    k = Keyword.get(opts, :k, 5)
    shuffle = Keyword.get(opts, :shuffle, true)
    seed = Keyword.get(opts, :seed, :rand.uniform(1_000_000))

    items =
      if shuffle do
        :rand.seed(:exsss, {seed, seed, seed})
        Enum.shuffle(dataset.items)
      else
        dataset.items
      end

    fold_size = div(length(items), k)

    folds =
      0..(k - 1)
      |> Enum.map(fn i ->
        test_start = i * fold_size
        test_end = min((i + 1) * fold_size, length(items))

        test_items = Enum.slice(items, test_start, test_end - test_start)
        train_items = Enum.take(items, test_start) ++ Enum.drop(items, test_end)

        train_dataset = %{
          dataset
          | name: "#{dataset.name}_fold#{i}_train",
            items: train_items,
            metadata:
              Map.merge(dataset.metadata, %{
                fold: i,
                split: :train,
                k_folds: k
              })
        }

        test_dataset = %{
          dataset
          | name: "#{dataset.name}_fold#{i}_test",
            items: test_items,
            metadata:
              Map.merge(dataset.metadata, %{
                fold: i,
                split: :test,
                k_folds: k
              })
        }

        {train_dataset, test_dataset}
      end)

    {:ok, folds}
  end

  @doc """
  Split dataset into train and test sets.

  ## Options
    * `:test_size` - Proportion for test set (0.0 to 1.0, default: 0.2)
    * `:shuffle` - Shuffle before splitting (default: true)
    * `:seed` - Random seed for shuffling (default: random)

  ## Examples

      {:ok, {train, test}} = HfDatasetsEx.Sampler.train_test_split(
        dataset,
        test_size: 0.2,
        shuffle: true
      )

      length(train.items) + length(test.items) == length(dataset.items)
      # => true
  """
  @spec train_test_split(Dataset.t(), keyword()) :: {:ok, {Dataset.t(), Dataset.t()}}
  def train_test_split(%Dataset{} = dataset, opts \\ []) do
    test_size = Keyword.get(opts, :test_size, 0.2)
    shuffle_opt = Keyword.get(opts, :shuffle, true)
    seed = Keyword.get(opts, :seed, :rand.uniform(1_000_000))

    items =
      if shuffle_opt do
        :rand.seed(:exsss, {seed, seed, seed})
        Enum.shuffle(dataset.items)
      else
        dataset.items
      end

    total = length(items)
    test_count = round(total * test_size)
    train_count = total - test_count

    train_items = Enum.take(items, train_count)
    test_items = Enum.drop(items, train_count)

    train_dataset = %{
      dataset
      | name: "#{dataset.name}_train",
        items: train_items,
        metadata: Map.merge(dataset.metadata, %{split: :train, split_ratio: 1.0 - test_size})
    }

    test_dataset = %{
      dataset
      | name: "#{dataset.name}_test",
        items: test_items,
        metadata: Map.merge(dataset.metadata, %{split: :test, split_ratio: test_size})
    }

    {:ok, {train_dataset, test_dataset}}
  end

  @doc """
  Shuffle the items in a dataset.

  ## Options
    * `:seed` - Random seed for reproducibility (default: random)

  ## Examples

      {:ok, shuffled} = HfDatasetsEx.Sampler.shuffle(dataset, seed: 42)

  """
  @spec shuffle(Dataset.t(), keyword()) :: {:ok, Dataset.t()}
  def shuffle(%Dataset{} = dataset, opts \\ []) do
    seed = Keyword.get(opts, :seed, :rand.uniform(1_000_000))

    :rand.seed(:exsss, {seed, seed, seed})

    shuffled_items = Enum.shuffle(dataset.items)

    shuffled_dataset = %{
      dataset
      | items: shuffled_items,
        metadata:
          Map.merge(dataset.metadata, %{
            shuffled: true,
            shuffle_seed: seed
          })
    }

    {:ok, shuffled_dataset}
  end

  @doc """
  Take the first n items from a dataset.

  ## Examples

      {:ok, subset} = HfDatasetsEx.Sampler.take(dataset, 100)

  """
  @spec take(Dataset.t(), non_neg_integer()) :: {:ok, Dataset.t()}
  def take(%Dataset{} = dataset, n) when is_integer(n) and n >= 0 do
    taken_items = Enum.take(dataset.items, n)

    taken_dataset = %{
      dataset
      | name: "#{dataset.name}_take_#{n}",
        items: taken_items,
        metadata:
          Map.merge(dataset.metadata, %{
            take_n: n,
            original_size: length(dataset.items)
          })
    }

    {:ok, taken_dataset}
  end

  @doc """
  Skip the first n items in a dataset.

  ## Examples

      {:ok, rest} = HfDatasetsEx.Sampler.skip(dataset, 100)

  """
  @spec skip(Dataset.t(), non_neg_integer()) :: {:ok, Dataset.t()}
  def skip(%Dataset{} = dataset, n) when is_integer(n) and n >= 0 do
    remaining_items = Enum.drop(dataset.items, n)

    skipped_dataset = %{
      dataset
      | name: "#{dataset.name}_skip_#{n}",
        items: remaining_items,
        metadata:
          Map.merge(dataset.metadata, %{
            skip_n: n,
            original_size: length(dataset.items)
          })
    }

    {:ok, skipped_dataset}
  end

  @doc """
  Filter items in a dataset by a predicate function.

  ## Examples

      # Keep only hard problems
      {:ok, hard} = HfDatasetsEx.Sampler.filter(dataset, fn item ->
        item.metadata.difficulty == "hard"
      end)

  """
  @spec filter(Dataset.t(), (map() -> boolean())) :: {:ok, Dataset.t()}
  def filter(%Dataset{} = dataset, predicate) when is_function(predicate, 1) do
    filtered_items = Enum.filter(dataset.items, predicate)

    filtered_dataset = %{
      dataset
      | name: "#{dataset.name}_filtered",
        items: filtered_items,
        metadata:
          Map.merge(dataset.metadata, %{
            filtered: true,
            original_size: length(dataset.items)
          })
    }

    {:ok, filtered_dataset}
  end
end
