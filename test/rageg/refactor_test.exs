defmodule Rageg.RefactorTest do
  use ExUnit.Case, async: true

  alias Rageg.Refactor

  describe "operations/0" do
    test "returns 6 operations with name, label, icon, description" do
      ops = Refactor.operations()

      assert [_, _, _, _, _, _] = ops

      for {_key, label, icon, desc} <- ops do
        assert is_binary(label)
        assert String.starts_with?(icon, "hero-")
        assert is_binary(desc)
      end
    end
  end

  describe "operation_fields/1" do
    test "returns fields for rename_function" do
      fields = Refactor.operation_fields(:rename_function)
      assert [_, _, _, _] = fields
      assert {:module, "Module", "text"} in fields
    end

    test "returns fields for rename_module" do
      fields = Refactor.operation_fields(:rename_module)
      assert [_, _] = fields
    end

    test "returns empty list for unknown operation" do
      assert [] = Refactor.operation_fields(:unknown_op)
    end
  end

  describe "undo_history/2" do
    test "does not crash for any path" do
      result = Refactor.undo_history("/nonexistent")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
