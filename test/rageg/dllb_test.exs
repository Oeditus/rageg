defmodule Rageg.DllbTest do
  use ExUnit.Case, async: true

  alias Rageg.Dllb

  describe "config/0" do
    test "returns connection configuration map" do
      config = Dllb.config()
      assert is_map(config)
      assert Map.has_key?(config, :host)
      assert Map.has_key?(config, :port)
      assert Map.has_key?(config, :pool_size)
      assert Map.has_key?(config, :enabled)
    end
  end

  describe "schema_fields/0" do
    test "returns 15 field tuples" do
      fields = Dllb.schema_fields()
      assert length(fields) == 15

      for {name, type, _req} <- fields do
        assert is_binary(name)
        assert is_binary(type)
      end
    end
  end

  describe "schema_indexes/0" do
    test "returns 10 index tuples" do
      indexes = Dllb.schema_indexes()
      assert length(indexes) == 10
    end
  end

  describe "meta_ast_node_types/0" do
    test "returns 38 node types" do
      types = Dllb.meta_ast_node_types()
      assert length(types) == 38
      assert "container" in types
      assert "function_def" in types
      assert "function_call" in types
    end
  end

  describe "supervision_tree/0" do
    test "returns a tree with root and children" do
      tree = Dllb.supervision_tree()
      assert tree.name == "dllb_sup"
      assert tree.strategy == "OneForAll"
      assert [_, _, _] = tree.children
    end
  end

  describe "edge_types/0" do
    test "returns 6 edge types" do
      types = Dllb.edge_types()
      assert [_, _, _, _, _, _] = types

      for {name, desc} <- types do
        assert is_binary(name)
        assert is_binary(desc)
      end
    end
  end

  describe "connected?/0" do
    test "returns false when dllb is not enabled" do
      refute Dllb.connected?()
    end
  end
end
