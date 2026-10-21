defmodule Rageg.WorkspaceTest do
  use ExUnit.Case, async: false

  alias Rageg.Workspace

  setup do
    previous = Application.get_env(:rageg, :allowed_roots)
    on_exit(fn -> restore(previous) end)
    :ok
  end

  defp restore(nil), do: Application.delete_env(:rageg, :allowed_roots)
  defp restore(value), do: Application.put_env(:rageg, :allowed_roots, value)

  defp allow(roots), do: Application.put_env(:rageg, :allowed_roots, roots)

  describe "allowed?/1 with no allowlist configured" do
    test "allows any path" do
      Application.delete_env(:rageg, :allowed_roots)

      refute Workspace.enforced?()
      assert Workspace.allowed?("/etc")
      assert Workspace.allowed?(System.tmp_dir!())
    end

    test "rejects nil" do
      refute Workspace.allowed?(nil)
    end
  end

  describe "allowed?/1 with an allowlist" do
    test "allows the root itself and paths beneath it" do
      allow(["/srv/repos"])

      assert Workspace.enforced?()
      assert Workspace.allowed?("/srv/repos")
      assert Workspace.allowed?("/srv/repos/rageg")
      assert Workspace.allowed?("/srv/repos/rageg/lib/rageg.ex")
    end

    test "rejects paths outside every root" do
      allow(["/srv/repos"])

      refute Workspace.allowed?("/etc/passwd")
      refute Workspace.allowed?("/srv/other")
      # Prefix match must respect path boundaries: /srv/reposX is not inside.
      refute Workspace.allowed?("/srv/reposX")
    end

    test "resolves .. traversal before checking" do
      allow(["/srv/repos"])

      refute Workspace.allowed?("/srv/repos/../../etc")
      assert Workspace.allowed?("/srv/repos/sub/../other")
    end

    test "expands ~ in configured roots" do
      allow(["~"])

      assert Workspace.allowed?(Path.join(System.user_home!(), "code/project"))
      refute Workspace.allowed?("/etc")
    end

    test "allows any of several roots" do
      allow(["/srv/repos", "/home/dev/code"])

      assert Workspace.allowed?("/home/dev/code/app")
      assert Workspace.allowed?("/srv/repos/app")
      refute Workspace.allowed?("/opt/app")
    end
  end

  describe "check/1" do
    test "returns :ok or an error tuple" do
      allow(["/srv/repos"])

      assert :ok = Workspace.check("/srv/repos/app")
      assert {:error, :path_not_allowed} = Workspace.check("/etc")
    end
  end

  describe "rejection_message/1" do
    test "names the path and the allowed roots" do
      allow(["/srv/repos"])

      message = Workspace.rejection_message("/etc/passwd")
      assert message =~ "/etc/passwd"
      assert message =~ "/srv/repos"
    end
  end
end
