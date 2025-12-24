defmodule HfDatasetsEx.PRNG.SeedSequence do
  @moduledoc """
  SeedSequence implementation matching NumPy's seeding algorithm.

  Converts an integer seed into the 128-bit state and increment values
  needed for PCG64, using the same hash-based mixing algorithm as NumPy.
  """

  import Bitwise

  # Hash constants from NumPy
  @init_a 0x43B0D7E5
  @mult_a 0x931E8875
  @init_b 0x8B51F9DD
  @mult_b 0x58F38DED
  @mix_mult_l 0xCA01F9DD
  @mix_mult_r 0x4973F715
  @xshift 16

  @mask32 0xFFFFFFFF

  @doc """
  Generate PCG64 state from an integer seed.

  Returns `{state_high, state_low, inc_high, inc_low}` matching NumPy's
  SeedSequence behavior.
  """
  @spec generate_pcg64_state(non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
  def generate_pcg64_state(seed) when is_integer(seed) and seed >= 0 do
    # Convert seed to uint32 array (little-endian)
    entropy = seed_to_uint32_array(seed)

    # Create pool of size 4 (128 bits)
    pool = mix_entropy(entropy, 4)

    # Generate 4 uint64 words for PCG64 state
    state_words = generate_state_words(pool, 4)

    # NumPy passes words as [0]=high, [1]=low to pcg64_set_seed
    # s = (seed[0] << 64) | seed[1], so word[0] is HIGH, word[1] is LOW
    state_high = Enum.at(state_words, 0)
    state_low = Enum.at(state_words, 1)
    inc_high = Enum.at(state_words, 2)
    inc_low = Enum.at(state_words, 3)

    {state_high, state_low, inc_high, inc_low}
  end

  # Convert seed integer to list of uint32 values (little-endian)
  defp seed_to_uint32_array(0), do: [0]

  defp seed_to_uint32_array(seed) do
    seed_to_uint32_array(seed, [])
  end

  defp seed_to_uint32_array(0, acc), do: Enum.reverse(acc)

  defp seed_to_uint32_array(seed, acc) do
    word = seed &&& @mask32
    seed_to_uint32_array(seed >>> 32, [word | acc])
  end

  # Mix entropy into pool using NumPy's algorithm
  defp mix_entropy(entropy, pool_size) do
    # Initialize pool with zeros
    pool = List.duplicate(0, pool_size)

    # Phase 1: Hash entropy into pool
    {pool, hash_const} =
      Enum.reduce(0..(pool_size - 1), {pool, @init_a}, fn i, {pool, hash_const} ->
        value = Enum.at(entropy, i, 0)
        {hashed, new_hash_const} = hashmix(value, hash_const)
        {List.replace_at(pool, i, hashed), new_hash_const}
      end)

    # Phase 2: Mix all bits together
    {pool, _hash_const} =
      Enum.reduce(0..(pool_size - 1), {pool, hash_const}, fn i_src, {pool, hash_const} ->
        Enum.reduce(0..(pool_size - 1), {pool, hash_const}, fn i_dst, {pool, hash_const} ->
          if i_src != i_dst do
            src_val = Enum.at(pool, i_src)
            dst_val = Enum.at(pool, i_dst)
            {hashed, new_hash_const} = hashmix(src_val, hash_const)
            mixed = mix(dst_val, hashed)
            {List.replace_at(pool, i_dst, mixed), new_hash_const}
          else
            {pool, hash_const}
          end
        end)
      end)

    # Phase 3: Mix remaining entropy (if any beyond pool_size)
    {pool, _} =
      Enum.reduce(pool_size..(length(entropy) - 1)//1, {pool, hash_const}, fn i_src,
                                                                              {pool, hash_const} ->
        Enum.reduce(0..(pool_size - 1), {pool, hash_const}, fn i_dst, {pool, hash_const} ->
          src_val = Enum.at(entropy, i_src)
          dst_val = Enum.at(pool, i_dst)
          {hashed, new_hash_const} = hashmix(src_val, hash_const)
          mixed = mix(dst_val, hashed)
          {List.replace_at(pool, i_dst, mixed), new_hash_const}
        end)
      end)

    pool
  end

  # Generate state words from pool (as uint64 values)
  defp generate_state_words(pool, n_words) do
    # We need n_words * 2 uint32 values, then combine into uint64
    n_uint32 = n_words * 2

    # Cycle through pool to generate uint32 words
    pool_cycle = Stream.cycle(pool)

    uint32_words =
      pool_cycle
      |> Stream.with_index()
      |> Enum.take(n_uint32)
      |> Enum.reduce({[], @init_b}, fn {pool_val, _idx}, {acc, hash_const} ->
        # XOR with hash_const, multiply, shift
        value = bxor(pool_val, hash_const) &&& @mask32
        hash_const = hash_const * @mult_b &&& @mask32
        value = value * hash_const &&& @mask32
        value = bxor(value, value >>> @xshift) &&& @mask32
        {[value | acc], hash_const}
      end)
      |> elem(0)
      |> Enum.reverse()

    # Combine pairs of uint32 into uint64 (little-endian)
    uint32_words
    |> Enum.chunk_every(2)
    |> Enum.map(fn [low, high] ->
      low ||| high <<< 32
    end)
  end

  # Hash mix function from NumPy
  defp hashmix(value, hash_const) do
    value = bxor(value, hash_const) &&& @mask32
    new_hash_const = hash_const * @mult_a &&& @mask32
    value = value * new_hash_const &&& @mask32
    value = bxor(value, value >>> @xshift) &&& @mask32
    {value, new_hash_const}
  end

  # Mix function from NumPy
  defp mix(x, y) do
    result = @mix_mult_l * x - @mix_mult_r * y &&& @mask32
    bxor(result, result >>> @xshift) &&& @mask32
  end
end
