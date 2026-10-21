defmodule Rageg.GraphPropertyTest do
  use ExUnit.Case, async: true

  use ExUnitProperties

  alias Rageg.Graph

  # Generators mirror the shapes `prettify_id/1` claims to understand, so the
  # properties below assert the *contract* (idempotence, format stability)
  # rather than re-testing hand-picked strings.

  defp identifier do
    gen all(
          head <- string([?a..?z, ?A..?Z], min_length: 1, max_length: 1),
          tail <- string([?a..?z, ?A..?Z, ?0..?9, ?_], max_length: 12)
        ) do
      head <> tail
    end
  end

  defp module_segment do
    gen all(segment <- identifier()) do
      String.capitalize(segment)
    end
  end

  defp module_name do
    gen all(
          first <- module_segment(),
          rest <- list_of(module_segment(), max_length: 3)
        ) do
      Enum.join([first | rest], ".")
    end
  end

  defp arity, do: integer(0..255)

  defp function_id do
    gen all(
          module <- module_name(),
          name <- identifier(),
          arity <- arity()
        ) do
      "#{module}.#{name}/#{arity}"
    end
  end

  property "prettify_id/1 is idempotent for well-formed function ids" do
    check all(id <- function_id()) do
      once = Graph.prettify_id(id)
      assert Graph.prettify_id(once) == once
    end
  end

  property "prettify_id/1 preserves well-formed function ids verbatim" do
    check all(id <- function_id()) do
      assert Graph.prettify_id(id) == id
    end
  end

  property "prettify_id/1 is idempotent for well-formed module names" do
    check all(module <- module_name()) do
      once = Graph.prettify_id(module)
      assert Graph.prettify_id(once) == once
    end
  end

  property "prettify_id/1 round-trips inspected tuples" do
    check all(
            module <- module_name(),
            name <- identifier(),
            arity <- arity()
          ) do
      inspected = "{:function, #{module}, :#{name}, #{arity}}"
      assert Graph.prettify_id(inspected) == "#{module}.#{name}/#{arity}"

      inspected_module = "{:module, #{module}}"
      assert Graph.prettify_id(inspected_module) == module
    end
  end

  property "prettify_id/1 never raises on arbitrary input" do
    check all(input <- string(:printable, max_length: 60)) do
      assert is_binary(Graph.prettify_id(input))
    end
  end
end
