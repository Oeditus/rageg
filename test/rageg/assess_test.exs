defmodule Rageg.AssessTest do
  use ExUnit.Case, async: true

  alias Rageg.Assess

  @repo_path File.cwd!()

  describe "list_branches/1" do
    test "lists branches for valid repository path" do
      assert {:ok, branches} = Assess.list_branches(@repo_path)
      assert is_list(branches)
      assert length(branches) > 0

      for branch <- branches do
        assert is_binary(branch.name)
        assert is_boolean(branch.current?)
        refute String.contains?(branch.name, "HEAD")
      end

      assert Enum.any?(branches, & &1.current?)
    end

    test "returns error for invalid repository path" do
      assert {:error, _reason} = Assess.list_branches("/invalid/repo/path")
    end
  end

  describe "current_branch/1" do
    test "returns current branch name for active repo" do
      assert {:ok, branch} = Assess.current_branch(@repo_path)
      assert is_binary(branch)
      assert String.length(branch) > 0
    end
  end

  describe "run/2" do
    test "returns no changes when diffing head against itself" do
      {:ok, current} = Assess.current_branch(@repo_path)

      assert {:ok, result} = Assess.run(@repo_path, base: current, head: current)
      assert result.changed_files == []
      assert result.summary.total_issues == 0
      assert result.report =~ "No files changed"
    end

    test "handles invalid base ref gracefully without crashing" do
      assert {:error, reason} =
               Assess.run(@repo_path, base: "invalid_non_existent_ref_12345", head: "main")

      assert is_binary(reason)
      refute reason =~ "fatal: ambiguous argument"
    end
  end
end
