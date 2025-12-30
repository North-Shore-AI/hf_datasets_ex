defmodule Mix.Tasks.HfDatasets.Test.Live do
  @shortdoc "Run hf_datasets_ex tests with live data sources"
  @moduledoc """
  Runs the test suite against live data sources.

  ## Usage

      # Run all tests with live data
      mix hf_datasets.test.live

      # Run specific test file with live data
      mix hf_datasets.test.live test/dataset_manager/loader/gsm8k_test.exs

      # Pass any mix test options
      mix hf_datasets.test.live --only integration --trace

  ## Configuration

  This task marks test mode as live so tests can opt into real data sources.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    # Also set an application env that tests can check
    Application.put_env(:hf_datasets_ex, :test_mode, :live)

    # Run the standard test task with all passed arguments
    Mix.Task.run("test", ensure_live_include(args))
  end

  defp ensure_live_include(args) do
    has_live =
      args
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.any?(fn
        ["--include", "live"] -> true
        ["--only", "live"] -> true
        _ -> false
      end)

    if has_live do
      args
    else
      ["--include", "live" | args]
    end
  end
end
