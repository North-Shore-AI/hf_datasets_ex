defmodule HfDatasetsEx.PRNG.PCG64 do
  @moduledoc """
  PCG64 pseudo-random number generator.

  This is a pure Elixir implementation of the PCG64 algorithm used by NumPy,
  ensuring identical random sequences for the same seed. This enables exact
  parity with Python's `datasets.shuffle(seed=N)`.

  ## Usage

  Most users should use `HfDatasetsEx.Dataset.shuffle/2` with the `:numpy` generator
  (the default) rather than calling this module directly:

      Dataset.shuffle(dataset, seed: 42)

  For direct usage:

      state = HfDatasetsEx.PRNG.PCG64.seed(42)
      {shuffled_list, _state} = HfDatasetsEx.PRNG.PCG64.shuffle(my_list, state)

  ## Algorithm

  PCG64 uses a 128-bit linear congruential generator with:
  - 128-bit state
  - 128-bit increment (always odd)
  - XSL-RR output function (XOR high/low, rotate right)

  ## References

  - https://www.pcg-random.org/
  - NumPy source: numpy/random/src/pcg64/pcg64.h
  """

  import Bitwise

  # PCG64 default multiplier (128-bit as {high, low})
  @multiplier_high 2_549_297_995_355_413_924
  @multiplier_low 4_865_540_595_714_422_341

  # Mask for 64-bit and 32-bit values
  @mask64 0xFFFFFFFFFFFFFFFF
  @mask32 0xFFFFFFFF

  @type state :: %{
          state_high: non_neg_integer(),
          state_low: non_neg_integer(),
          inc_high: non_neg_integer(),
          inc_low: non_neg_integer(),
          has_uint32: boolean(),
          uinteger: non_neg_integer()
        }

  @doc """
  Create a new PCG64 state seeded with the given value.

  Matches NumPy's seeding behavior for `numpy.random.Generator(PCG64(seed))`.
  Uses SeedSequence to generate the full 128-bit state and increment.
  """
  @spec seed(non_neg_integer()) :: state()
  def seed(seed_value) when is_integer(seed_value) and seed_value >= 0 do
    # Use SeedSequence to generate state (matches NumPy exactly)
    {state_high, state_low, inc_high, inc_low} =
      HfDatasetsEx.PRNG.SeedSequence.generate_pcg64_state(seed_value)

    # Apply PCG64 seeding algorithm
    seed_with_state(state_high, state_low, inc_high, inc_low)
  end

  @doc """
  Create PCG64 state from explicit state/increment values.
  """
  @spec seed_with_state(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: state()
  def seed_with_state(init_state_high, init_state_low, init_inc_high, init_inc_low) do
    # Ensure increment is odd (shift left 1, set low bit)
    inc_low = (init_inc_low <<< 1 ||| 1) &&& @mask64
    inc_high = (init_inc_high <<< 1 ||| init_inc_low >>> 63) &&& @mask64

    state = %{
      state_high: 0,
      state_low: 0,
      inc_high: inc_high,
      inc_low: inc_low,
      has_uint32: false,
      uinteger: 0
    }

    # Step once
    state = step(state)

    # Add initstate
    {new_high, new_low} =
      add_128(
        {state.state_high, state.state_low},
        {init_state_high, init_state_low}
      )

    state = %{state | state_high: new_high, state_low: new_low}

    # Step again
    step(state)
  end

  @doc """
  Create a new PCG64 state with explicit 128-bit initstate and initseq.
  """
  @spec seed_128({non_neg_integer(), non_neg_integer()}, {non_neg_integer(), non_neg_integer()}) ::
          state()
  def seed_128({init_high, init_low}, {seq_high, seq_low}) do
    # Step 1: Initialize state to 0, set increment from initseq
    # inc = (initseq << 1) | 1  (ensures odd)
    inc_low = (seq_low <<< 1 ||| 1) &&& @mask64
    inc_high = (seq_high <<< 1 ||| seq_low >>> 63) &&& @mask64

    state = %{
      state_high: 0,
      state_low: 0,
      inc_high: inc_high,
      inc_low: inc_low,
      has_uint32: false,
      uinteger: 0
    }

    # Step 2: Advance state once
    state = step(state)

    # Step 3: Add initstate to current state
    {new_high, new_low} =
      add_128(
        {state.state_high, state.state_low},
        {init_high, init_low}
      )

    state = %{state | state_high: new_high, state_low: new_low}

    # Step 4: Advance state again
    step(state)
  end

  @doc """
  Generate the next 64-bit random number and return updated state.
  Clears the uint32 buffer.
  """
  @spec next(state()) :: {non_neg_integer(), state()}
  def next(state) do
    # Advance state: state = state * multiplier + increment
    new_state = step(state)

    # Output function: XSL-RR
    # XOR high and low parts of NEW state, then rotate right
    xored = bxor(new_state.state_high, new_state.state_low) &&& @mask64
    rot = new_state.state_high >>> 58
    output = rotate_right_64(xored, rot)

    # Clear uint32 buffer (consistent with how numpy handles this)
    {output, %{new_state | has_uint32: false, uinteger: 0}}
  end

  @doc """
  Generate the next 32-bit random number and return updated state.

  NumPy's PCG64 uses buffered 32-bit output: generates a 64-bit value,
  returns low 32 bits first, caches high 32 bits for next call.
  This matches numpy's pcg64_next32 exactly.
  """
  @spec next32(state()) :: {non_neg_integer(), state()}
  def next32(state) do
    if state.has_uint32 do
      # Return cached high 32 bits
      {state.uinteger, %{state | has_uint32: false, uinteger: 0}}
    else
      # Generate new 64-bit value
      new_state = step(state)
      xored = bxor(new_state.state_high, new_state.state_low) &&& @mask64
      rot = new_state.state_high >>> 58
      output64 = rotate_right_64(xored, rot)

      # Cache high 32 bits, return low 32 bits
      low32 = output64 &&& @mask32
      high32 = output64 >>> 32 &&& @mask32
      {low32, %{new_state | has_uint32: true, uinteger: high32}}
    end
  end

  @doc """
  Generate a random integer in range [0, max] (inclusive).

  Uses rejection sampling with bitmask for uniform distribution.
  Matches numpy's random_interval: uses 32-bit for small max, 64-bit for large.
  """
  @spec random_interval(state(), non_neg_integer()) :: {non_neg_integer(), state()}
  def random_interval(state, 0), do: {0, state}

  def random_interval(state, max) when is_integer(max) and max > 0 do
    # Create bitmask covering max
    mask = create_mask(max)

    # NumPy uses 32-bit random for max <= 0xFFFFFFFF, 64-bit otherwise
    if max <= @mask32 do
      rejection_sample_32(state, max, mask)
    else
      rejection_sample_64(state, max, mask)
    end
  end

  @doc """
  Shuffle a list deterministically using Fisher-Yates algorithm.

  Produces identical results to NumPy's shuffle with the same seed.
  """
  @spec shuffle(list(), state()) :: {list(), state()}
  def shuffle([], state), do: {[], state}
  def shuffle([_] = list, state), do: {list, state}

  def shuffle(list, state) when is_list(list) do
    arr = :array.from_list(list)
    n = :array.size(arr)

    {shuffled_arr, final_state} = fisher_yates(arr, n - 1, state)

    {:array.to_list(shuffled_arr), final_state}
  end

  # Fisher-Yates shuffle (iterate backwards from n-1 to 1)
  defp fisher_yates(arr, 0, state), do: {arr, state}

  defp fisher_yates(arr, i, state) do
    # Generate random index j in [0, i]
    {j, state} = random_interval(state, i)

    # Swap elements at i and j
    arr =
      if i != j do
        val_i = :array.get(i, arr)
        val_j = :array.get(j, arr)
        arr = :array.set(i, val_j, arr)
        :array.set(j, val_i, arr)
      else
        arr
      end

    fisher_yates(arr, i - 1, state)
  end

  # Advance the LCG state: state = state * multiplier + increment
  defp step(state) do
    {mult_high, mult_low} =
      mult_128(
        {state.state_high, state.state_low},
        {@multiplier_high, @multiplier_low}
      )

    {new_high, new_low} =
      add_128(
        {mult_high, mult_low},
        {state.inc_high, state.inc_low}
      )

    %{state | state_high: new_high, state_low: new_low}
  end

  # 128-bit addition with carry
  defp add_128({a_high, a_low}, {b_high, b_low}) do
    low = a_low + b_low &&& @mask64
    # Carry if overflow occurred
    carry = if low < a_low, do: 1, else: 0
    high = a_high + b_high + carry &&& @mask64
    {high, low}
  end

  # 128-bit multiplication
  # (a_high, a_low) * (b_high, b_low) = result (128-bit, ignoring overflow)
  defp mult_128({a_high, a_low}, {b_high, b_low}) do
    # Low part: a_low * b_low (need full 128-bit result)
    {prod_high, prod_low} = mult_64_full(a_low, b_low)

    # Add cross products to high part
    cross1 = a_high * b_low &&& @mask64
    cross2 = a_low * b_high &&& @mask64
    high = prod_high + cross1 + cross2 &&& @mask64

    {high, prod_low}
  end

  # Multiply two 64-bit values, return full 128-bit result as {high, low}
  defp mult_64_full(x, y) do
    # Split into 32-bit parts
    x0 = x &&& 0xFFFFFFFF
    x1 = x >>> 32
    y0 = y &&& 0xFFFFFFFF
    y1 = y >>> 32

    # Partial products
    p00 = x0 * y0
    p01 = x0 * y1
    p10 = x1 * y0
    p11 = x1 * y1

    # Combine
    # low = (p00) + (p01 << 32) + (p10 << 32)  [lower 64 bits]
    # high = (p11) + (p01 >> 32) + (p10 >> 32) + carries

    mid = p01 + p10
    # Check for carry in mid sum
    mid_carry = if mid < p01, do: 1 <<< 32, else: 0

    low = p00 + (mid <<< 32) &&& @mask64
    # Carry from low addition
    low_carry = if low < p00, do: 1, else: 0

    high = p11 + (mid >>> 32) + mid_carry + low_carry &&& @mask64

    {high, low}
  end

  # Rotate right a 64-bit value
  defp rotate_right_64(value, 0), do: value &&& @mask64

  defp rotate_right_64(value, rot) when rot > 0 and rot < 64 do
    (value >>> rot ||| value <<< (64 - rot)) &&& @mask64
  end

  # Create smallest bitmask >= value
  defp create_mask(value) do
    mask = value
    mask = mask ||| mask >>> 1
    mask = mask ||| mask >>> 2
    mask = mask ||| mask >>> 4
    mask = mask ||| mask >>> 8
    mask = mask ||| mask >>> 16
    mask ||| mask >>> 32
  end

  # Rejection sampling for uniform distribution using 32-bit values
  defp rejection_sample_32(state, max, mask) do
    {value, state} = next32(state)
    masked = value &&& mask

    if masked <= max do
      {masked, state}
    else
      rejection_sample_32(state, max, mask)
    end
  end

  # Rejection sampling for uniform distribution using 64-bit values
  defp rejection_sample_64(state, max, mask) do
    {value, state} = next(state)
    masked = value &&& mask

    if masked <= max do
      {masked, state}
    else
      rejection_sample_64(state, max, mask)
    end
  end
end
