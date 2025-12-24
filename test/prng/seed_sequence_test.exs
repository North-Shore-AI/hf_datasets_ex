defmodule HfDatasetsEx.PRNG.SeedSequenceTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.PRNG.SeedSequence

  describe "generate_pcg64_state/1" do
    test "returns 4-tuple of integers" do
      {state_high, state_low, inc_high, inc_low} = SeedSequence.generate_pcg64_state(42)

      assert is_integer(state_high)
      assert is_integer(state_low)
      assert is_integer(inc_high)
      assert is_integer(inc_low)
    end

    test "returns non-negative values" do
      {state_high, state_low, inc_high, inc_low} = SeedSequence.generate_pcg64_state(42)

      assert state_high >= 0
      assert state_low >= 0
      assert inc_high >= 0
      assert inc_low >= 0
    end

    test "returns 64-bit values" do
      {state_high, state_low, inc_high, inc_low} = SeedSequence.generate_pcg64_state(42)

      max_64 = 0xFFFFFFFFFFFFFFFF
      assert state_high <= max_64
      assert state_low <= max_64
      assert inc_high <= max_64
      assert inc_low <= max_64
    end

    test "same seed produces same state" do
      result1 = SeedSequence.generate_pcg64_state(12345)
      result2 = SeedSequence.generate_pcg64_state(12345)

      assert result1 == result2
    end

    test "different seeds produce different states" do
      result1 = SeedSequence.generate_pcg64_state(42)
      result2 = SeedSequence.generate_pcg64_state(43)

      refute result1 == result2
    end

    test "handles seed 0" do
      result = SeedSequence.generate_pcg64_state(0)
      assert tuple_size(result) == 4
    end

    test "handles small seeds" do
      for seed <- 0..10 do
        result = SeedSequence.generate_pcg64_state(seed)
        assert tuple_size(result) == 4
      end
    end

    test "handles large seeds" do
      large_seed = 0xFFFFFFFFFFFFFFFF
      result = SeedSequence.generate_pcg64_state(large_seed)
      assert tuple_size(result) == 4
    end

    test "handles very large seeds (> 64 bits)" do
      very_large_seed = 0xFFFFFFFFFFFFFFFFFFFFFFFF
      result = SeedSequence.generate_pcg64_state(very_large_seed)
      assert tuple_size(result) == 4
    end

    test "consecutive seeds produce different states" do
      states =
        for seed <- 0..20 do
          SeedSequence.generate_pcg64_state(seed)
        end

      unique_states = Enum.uniq(states)
      assert length(unique_states) == 21
    end

    test "state values have good bit distribution" do
      # Check that various seeds produce states with bits set in different positions
      seeds = [0, 1, 42, 1000, 999_999, 0xDEADBEEF]

      states =
        Enum.map(seeds, fn seed ->
          {sh, sl, ih, il} = SeedSequence.generate_pcg64_state(seed)
          # Combine into a single large integer for analysis
          sh + sl + ih + il
        end)

      # All should be different
      assert length(Enum.uniq(states)) == length(seeds)

      # All should be non-zero (entropy was mixed in)
      assert Enum.all?(states, fn s -> s > 0 end)
    end
  end

  describe "hash mixing properties" do
    test "small differences in seed produce large differences in state" do
      {sh1, sl1, ih1, il1} = SeedSequence.generate_pcg64_state(0)
      {sh2, sl2, ih2, il2} = SeedSequence.generate_pcg64_state(1)

      # States should differ significantly despite seeds differing by only 1
      state1_sum = sh1 + sl1 + ih1 + il1
      state2_sum = sh2 + sl2 + ih2 + il2

      # They should be completely different (avalanche effect)
      diff = abs(state1_sum - state2_sum)
      assert diff > 1_000_000, "Expected large difference, got #{diff}"
    end

    test "state components are independent" do
      results =
        for seed <- 0..99 do
          SeedSequence.generate_pcg64_state(seed)
        end

      # Extract each component
      state_highs = Enum.map(results, fn {sh, _, _, _} -> sh end)
      state_lows = Enum.map(results, fn {_, sl, _, _} -> sl end)
      inc_highs = Enum.map(results, fn {_, _, ih, _} -> ih end)
      inc_lows = Enum.map(results, fn {_, _, _, il} -> il end)

      # Each component should have significant variation
      assert length(Enum.uniq(state_highs)) > 90
      assert length(Enum.uniq(state_lows)) > 90
      assert length(Enum.uniq(inc_highs)) > 90
      assert length(Enum.uniq(inc_lows)) > 90
    end
  end

  describe "integration with PCG64" do
    alias HfDatasetsEx.PRNG.PCG64

    test "SeedSequence output works with PCG64.seed_with_state" do
      {sh, sl, ih, il} = SeedSequence.generate_pcg64_state(42)
      state = PCG64.seed_with_state(sh, sl, ih, il)

      # Should be able to generate random numbers
      {value, _state} = PCG64.next(state)
      assert is_integer(value)
      assert value >= 0
    end

    test "PCG64.seed uses SeedSequence internally" do
      # PCG64.seed(42) should produce same results as manual SeedSequence + seed_with_state
      direct_state = PCG64.seed(42)

      {sh, sl, ih, il} = SeedSequence.generate_pcg64_state(42)
      manual_state = PCG64.seed_with_state(sh, sl, ih, il)

      # The final states should match
      assert direct_state.state_high == manual_state.state_high
      assert direct_state.state_low == manual_state.state_low
      assert direct_state.inc_high == manual_state.inc_high
      assert direct_state.inc_low == manual_state.inc_low
    end
  end
end
