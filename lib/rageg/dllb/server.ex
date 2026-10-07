defmodule Rageg.Dllb.Server do
  @moduledoc """
  Manages the `dllb-server` development process lifecycle.

  Runs as a Phoenix endpoint watcher in `:dev` mode, automatically
  starting `dllb-server` if it is not already running.
  """

  require Logger

  @doc """
  Runs `dllb-server` as a Phoenix watcher process.

  If a server is already listening on the configured host and port, this
  function sleeps to avoid port and database lock conflicts. When no
  instance is running, it locates the `dllb-server` executable and spawns
  it in the foreground with standard input monitored for clean termination.
  """
  @spec watch(keyword()) :: :ok
  def watch(_opts \\ []) do
    if Application.get_env(:dllb, :enabled, false) do
      host = Application.get_env(:dllb, :host, "127.0.0.1")
      port = Application.get_env(:dllb, :port, 3009)

      if port_listening?(host, port) do
        Logger.info("[Rageg.Dllb.Server] dllb-server already listening on #{host}:#{port}")
        Process.sleep(:infinity)
      else
        case find_executable() do
          nil ->
            Logger.warning(
              "[Rageg.Dllb.Server] dllb-server binary not found. " <>
                "Please compile it ('cargo build --release -p dllb-server') or place it in PATH."
            )

            Process.sleep(:infinity)

          bin ->
            Logger.info("[Rageg.Dllb.Server] Starting dllb-server on #{host}:#{port} (#{bin})...")

            env = [
              {"DLLB_BIND", "#{host}:#{port}"},
              {"DLLB_PATH", System.get_env("DLLB_PATH", "dllb_dev.redb")},
              {"DLLB_LOG", System.get_env("DLLB_LOG", "info")},
              {"DLLB_WATCH_STDIN", "1"}
            ]

            cmd_opts = [
              env: env,
              into: IO.stream(:stdio, :line),
              stderr_to_stdout: true
            ]

            case System.cmd(bin, [], cmd_opts) do
              {_, 0} ->
                :ok

              {_, status} ->
                Logger.warning("[Rageg.Dllb.Server] dllb-server exited with status #{status}")
                Process.sleep(2000)
                :ok
            end
        end
      end
    else
      Process.sleep(:infinity)
    end
  end

  @doc "Checks if host:port is currently accepting TCP connections."
  @spec port_listening?(String.t(), :inet.port_number()) :: boolean()
  def port_listening?(host, port) do
    case :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false], 200) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  @doc "Finds the dllb-server executable binary."
  @spec find_executable() :: String.t() | nil
  def find_executable do
    custom =
      Application.get_env(:dllb, :server_bin) ||
        Application.get_env(:ragex, :dllb_server_bin) ||
        System.get_env("DLLB_SERVER_BIN")

    cond do
      custom && File.exists?(custom) ->
        custom

      exec = System.find_executable("dllb-server") ->
        exec

      true ->
        cwd = File.cwd!()
        local_bin = Path.expand("~/.local/bin/dllb-server")
        release_bin = Path.expand("../dllb/target/release/dllb-server", cwd)
        debug_bin = Path.expand("../dllb/target/debug/dllb-server", cwd)

        cond do
          File.exists?(local_bin) -> local_bin
          File.exists?(release_bin) -> release_bin
          File.exists?(debug_bin) -> debug_bin
          true -> nil
        end
    end
  end
end
