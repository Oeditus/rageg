defmodule Rageg.DiagnosticsTest do
  use ExUnit.Case, async: false

  alias Rageg.Diagnostics

  setup do
    Diagnostics.clear()
    on_exit(&Diagnostics.clear/0)
    :ok
  end

  describe "suppressed/3" do
    test "returns the fallback and records the operation" do
      assert Diagnostics.suppressed(:demo_op, %RuntimeError{message: "boom"}, []) == []

      report = Diagnostics.report()
      assert %{count: 1, last_reason: "boom"} = report[:demo_op]
    end

    test "accumulates counts for repeated failures" do
      for _ <- 1..3 do
        Diagnostics.suppressed(:repeat, %RuntimeError{message: "again"}, :fallback)
      end

      assert %{count: 3} = Diagnostics.report()[:repeat]
    end

    test "accepts non-exception reasons" do
      Diagnostics.suppressed(:exit_case, {:exit, :timeout}, nil)
      assert %{last_reason: "exit: :timeout"} = Diagnostics.report()[:exit_case]
    end
  end

  describe "degraded?/0" do
    test "is false before anything fails" do
      refute Diagnostics.degraded?()
      assert Diagnostics.degraded_count() == 0
    end

    test "becomes true once an error is recorded" do
      Diagnostics.suppressed(:something, %RuntimeError{message: "x"})
      assert Diagnostics.degraded?()
      assert Diagnostics.degraded_count() == 1
    end
  end

  describe "clear/0" do
    test "resets the report" do
      Diagnostics.suppressed(:something, %RuntimeError{message: "x"})
      assert :ok = Diagnostics.clear()
      refute Diagnostics.degraded?()
      assert Diagnostics.report() == %{}
    end
  end
end
