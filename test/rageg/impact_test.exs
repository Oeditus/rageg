defmodule Rageg.ImpactTest do
  use ExUnit.Case, async: true

  alias Rageg.Impact

  describe "effort_operations/0" do
    test "returns 6 operations" do
      ops = Impact.effort_operations()

      assert [_, _, _, _, _, _] = ops

      for {key, label} <- ops do
        assert is_atom(key)
        assert is_binary(label)
      end
    end
  end

  describe "analyze_change/2" do
    test "handles nonexistent target gracefully" do
      result = Impact.analyze_change("NonExistent.func/0")
      # Either returns analysis or error -- should not crash
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "risk_score/1" do
    test "handles nonexistent target gracefully" do
      result = Impact.risk_score("NonExistent.func/0")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
