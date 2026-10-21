defmodule Rageg.ImpactPropertyTest do
  use ExUnit.Case, async: true

  use ExUnitProperties

  alias Rageg.Impact

  # `parse_node_ref/1` and `format_ref/1` are inverses for well-formed
  # references, and formatting is stable. Both are pure, so they are ideal
  # property-test targets.
  #
  # `parse_node_ref/1` deliberately refuses to create atoms (user input must
  # never grow the atom table), so the generated modules/functions are
  # *actually defined* below rather than invented at test time.

  defmodule Alpha do
    def placeholder, do: :ok
  end

  defmodule Alpha.Beta do
    def placeholder, do: :ok
  end

  defmodule Gamma.Delta.Epsilon do
    def placeholder, do: :ok
  end

  @modules [Alpha, Alpha.Beta, Gamma.Delta.Epsilon]

  # `parse_node_ref/1` resolves atoms by their *existing* name, so we generate
  # the fully-qualified form (`Elixir.Rageg.ImpactPropertyTest.Alpha`) that
  # `Atom.to_string/1` produces.
  defp module_name, do: member_of(@modules) |> map(&Atom.to_string/1)

  defp identifier do
    gen all(
          head <- string([?a..?z, ?_], min_length: 1, max_length: 1),
          tail <- string([?a..?z, ?0..?9, ?_], max_length: 12)
        ) do
      head <> tail
    end
  end

  property "function refs round-trip through parse_node_ref/format_ref" do
    check all(
            module <- module_name(),
            name <- identifier(),
            arity <- integer(0..255)
          ) do
      # The function atom must exist for parse_node_ref/1 to accept it.
      _ = String.to_atom(name)

      ref = "#{module}.#{name}/#{arity}"
      parsed = Impact.parse_node_ref(ref)

      assert parsed == {:function, String.to_atom(module), String.to_atom(name), arity}
      assert Impact.format_ref(parsed) == ref
    end
  end

  property "module refs round-trip through parse_node_ref/format_ref" do
    check all(module <- module_name()) do
      parsed = Impact.parse_node_ref(module)

      assert parsed == {:module, String.to_atom(module)}
      assert Impact.format_ref(parsed) == module
    end
  end

  property "format_ref/1 is idempotent" do
    check all(
            module <- module_name(),
            name <- identifier(),
            arity <- integer(0..255)
          ) do
      _ = String.to_atom(name)

      once = Impact.format_ref(Impact.parse_node_ref("#{module}.#{name}/#{arity}"))
      assert Impact.format_ref(Impact.parse_node_ref(once)) == once
    end
  end

  property "unknown atoms are rejected rather than created" do
    check all(suffix <- positive_integer()) do
      ref = "Rageg.Definitely.Not.A.Module#{suffix}.fun/1"

      assert_raise ArgumentError, fn -> Impact.parse_node_ref(ref) end
    end
  end
end
