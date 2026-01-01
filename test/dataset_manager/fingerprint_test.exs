defmodule HfDatasetsEx.FingerprintTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.{Dataset, Fingerprint}

  describe "generate/3" do
    test "same inputs produce same fingerprint" do
      fp1 = Fingerprint.generate(:map, [&String.upcase/1], [])
      fp2 = Fingerprint.generate(:map, [&String.upcase/1], [])

      assert fp1 == fp2
    end

    test "different operations produce different fingerprints" do
      fp1 = Fingerprint.generate(:map, [&String.upcase/1], [])
      fp2 = Fingerprint.generate(:filter, [&String.upcase/1], [])

      assert fp1 != fp2
    end

    test "different args produce different fingerprints" do
      fp1 = Fingerprint.generate(:map, [&String.upcase/1], [])
      fp2 = Fingerprint.generate(:map, [&String.downcase/1], [])

      assert fp1 != fp2
    end

    test "different opts produce different fingerprints" do
      fp1 = Fingerprint.generate(:map, [], batched: true)
      fp2 = Fingerprint.generate(:map, [], batched: false)

      assert fp1 != fp2
    end

    test "fingerprint is 64 hex characters" do
      fp = Fingerprint.generate(:test, [])

      assert String.length(fp) == 64
      assert Regex.match?(~r/^[0-9a-f]+$/, fp)
    end
  end

  describe "from_dataset/1" do
    test "same dataset produces same fingerprint" do
      ds = Dataset.from_list([%{"x" => 1}, %{"x" => 2}])

      fp1 = Fingerprint.from_dataset(ds)
      fp2 = Fingerprint.from_dataset(ds)

      assert fp1 == fp2
    end

    test "different data produces different fingerprints" do
      ds1 = Dataset.from_list([%{"x" => 1}])
      ds2 = Dataset.from_list([%{"x" => 2}])

      assert Fingerprint.from_dataset(ds1) != Fingerprint.from_dataset(ds2)
    end
  end

  describe "combine/2" do
    test "combine is deterministic" do
      fp1 = Fingerprint.generate(:a, [])
      fp2 = Fingerprint.generate(:b, [])

      combined1 = Fingerprint.combine(fp1, fp2)
      combined2 = Fingerprint.combine(fp1, fp2)

      assert combined1 == combined2
    end

    test "combine is order-dependent" do
      fp1 = Fingerprint.generate(:a, [])
      fp2 = Fingerprint.generate(:b, [])

      assert Fingerprint.combine(fp1, fp2) != Fingerprint.combine(fp2, fp1)
    end
  end
end
