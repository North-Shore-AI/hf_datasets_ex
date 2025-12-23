defmodule TestSupport.HfCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      use ExUnit.Case, async: false
    end
  end

  setup_all context do
    if context[:live] do
      {:ok, stub: nil}
    else
      {:ok, stub} = TestSupport.HfStub.start()
      on_exit(fn -> TestSupport.HfStub.stop(stub) end)
      {:ok, stub: stub}
    end
  end

  setup context do
    if context[:live] do
      TestSupport.HfStub.clear_env()
    else
      if context[:stub], do: TestSupport.HfStub.apply_env(context[:stub])
    end

    :ok
  end
end
