# Exclude live and slow tests by default
# Run with: mix test --include live --include slow
#
# To run tests with live data sources:
#   mix test.live
Code.require_file(Path.expand("support/hf_stub.ex", __DIR__))
Code.require_file(Path.expand("support/hf_case.ex", __DIR__))
Code.require_file(Path.expand("support/parquet_backend.ex", __DIR__))
ExUnit.start(exclude: [:live, :slow])
ExUnit.after_suite(fn _ -> TestSupport.HfStub.cleanup_cache() end)

defmodule TestHelper do
  @moduledoc "Test utilities for data source control"

  def live_mode?, do: Application.get_env(:hf_datasets_ex, :test_mode) == :live

  def data_opts(extra \\ []) do
    Keyword.merge([], extra)
  end
end
