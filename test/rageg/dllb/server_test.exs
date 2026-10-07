defmodule Rageg.Dllb.ServerTest do
  use ExUnit.Case, async: false

  alias Rageg.Dllb.Server

  describe "find_executable/0" do
    test "locates dllb-server or returns nil" do
      # When dllb-server exists on the machine, find_executable should find it
      result = Server.find_executable()
      assert is_nil(result) or (is_binary(result) and File.exists?(result))
    end

    test "respects custom application environment" do
      tmp_file =
        Path.join(System.tmp_dir!(), "custom_dllb_server_#{System.unique_integer([:positive])}")

      File.touch!(tmp_file)

      on_exit(fn ->
        File.rm(tmp_file)
        Application.delete_env(:dllb, :server_bin)
      end)

      Application.put_env(:dllb, :server_bin, tmp_file)
      assert Server.find_executable() == tmp_file
    end
  end

  describe "port_listening?/2" do
    test "returns false for an unused port" do
      refute Server.port_listening?("127.0.0.1", 59_999)
    end

    test "returns true when a port is open" do
      {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
      {:ok, port} = :inet.port(socket)

      try do
        assert Server.port_listening?("127.0.0.1", port)
      after
        :gen_tcp.close(socket)
      end
    end
  end

  describe "watch/0" do
    test "returns cleanly or sleeps when dllb is disabled" do
      # In test environment, dllb is disabled by default
      Application.put_env(:dllb, :enabled, false)

      task = Task.async(fn -> Server.watch([]) end)
      # Give it a brief moment
      Process.sleep(50)
      Task.shutdown(task, :brutal_kill)
    end
  end
end
