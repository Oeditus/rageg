defmodule Rageg.NxBackend do
  @moduledoc """
  Selects the Nx/EXLA backend at runtime.

  Driven by `config :rageg, :nx_acceleration`:

    * `:auto` (dev/prod) - use the CUDA GPU client when a CUDA device is
      actually available, otherwise transparently fall back to the CPU
      (`:host`) client. The CUDA probe is crash-safe: it pre-checks driver
      health out-of-process (via `nvidia-smi`) so a driver/library version
      mismatch cannot abort the VM.
    * `:cuda` - force the CUDA client; logs a warning and falls back to
      `:host` if no CUDA device is present.
    * `:host` (test/CI) - always use the CPU client and skip the CUDA probe.

  The chosen client is applied both as EXLA's `:default_client` (used by
  `defn`/`Nx.Serving` compilation, e.g. Bumblebee servings) and as the global
  Nx default backend (used for tensor allocation).
  """

  require Logger

  @doc """
  Resolves the configured acceleration preference and installs the matching
  EXLA backend. Returns the selected client name (`:cuda` or `:host`).
  """
  @spec setup() :: :cuda | :host
  def setup do
    preference = Application.get_env(:rageg, :nx_acceleration, :auto)
    client = choose_client(preference)

    Application.put_env(:exla, :default_client, client)
    Nx.global_default_backend({EXLA.Backend, client: client})

    Logger.info(
      "Nx default backend set to EXLA (client: #{inspect(client)}, acceleration: #{inspect(preference)})"
    )

    client
  end

  defp choose_client(:host), do: :host

  defp choose_client(:cuda) do
    if cuda_available?() do
      :cuda
    else
      Logger.warning(":nx_acceleration is :cuda but no CUDA device is available; using :host")
      :host
    end
  end

  defp choose_client(:auto) do
    if cuda_available?() do
      :cuda
    else
      Logger.info("No CUDA device available; using CPU backend (:host)")
      :host
    end
  end

  defp choose_client(other) do
    Logger.warning("Unknown :nx_acceleration #{inspect(other)}; using :host")
    :host
  end

  # `cuda_available?/0` must never crash the VM. Two native-level failure modes
  # matter here, and neither is a normal Elixir exception:
  #
  #   1. Driver/library version mismatch -- common right after an NVIDIA driver
  #      update, before the kernel module is reloaded (or the box rebooted).
  #      `nvmlInit`/`cuInit` then abort with a SIGSEGV, an OS-level crash the
  #      `rescue`/`catch` clauses below cannot intercept. We defend against it
  #      by first running an out-of-process `nvidia-smi` health check and only
  #      touching EXLA's CUDA path when the driver is healthy.
  #
  #   2. Truncated/corrupt prebuilt `libxla_extension.so` -- e.g. an interrupted
  #      `mix deps.compile`/extraction leaves the ELF missing its trailing
  #      section headers, so `dlopen` SIGSEGVs while loading the NIF. This one
  #      cannot be guarded in-process at all; the remedy is to re-extract the
  #      XLA archive (`rm -rf deps/exla/cache/xla_extension` then recompile).
  #      It is called out here so the crash is recognizable next time.
  #
  # A CUDA platform with at least one device means the GPU is usable.
  defp cuda_available? do
    driver_healthy?() and exla_reports_cuda?()
  end

  # Out-of-process driver probe. Running bare `nvidia-smi` forces a full NVML
  # init, which exits non-zero on a driver/library mismatch ("Failed to
  # initialize NVML: Driver/library version mismatch"). Note a lighter call like
  # `nvidia-smi -L` skips that version handshake and can report success while
  # the driver is actually mismatched, so we intentionally avoid it here. This
  # lets us fall back to the CPU without ever loading CUDA into (and crashing)
  # this VM.
  defp driver_healthy? do
    case System.find_executable("nvidia-smi") do
      nil ->
        Logger.info("nvidia-smi not found; assuming no usable CUDA driver, using :host")
        false

      path ->
        case System.cmd(path, [], stderr_to_stdout: true) do
          {_out, 0} ->
            true

          {out, status} ->
            Logger.warning(
              "NVIDIA driver health check failed (exit #{status}): #{first_line(out)}. " <>
                "If you just updated the driver, a reboot is likely required. " <>
                "Falling back to CPU (:host)."
            )

            false
        end
    end
  rescue
    exception ->
      Logger.warning("NVIDIA driver health check errored: #{Exception.message(exception)}")
      false
  end

  # Ask EXLA which platforms it can see. Only safe to call once the driver is
  # known healthy. Still guarded defensively for any catchable failure.
  defp exla_reports_cuda? do
    case EXLA.Client.get_supported_platforms() do
      %{cuda: device_count} when is_integer(device_count) and device_count > 0 -> true
      _ -> false
    end
  rescue
    exception ->
      Logger.warning("CUDA availability probe failed: #{Exception.message(exception)}")
      false
  catch
    kind, reason ->
      Logger.warning("CUDA availability probe error: #{inspect({kind, reason})}")
      false
  end

  defp first_line(output) do
    output
    |> String.split("\n", trim: true)
    |> List.first("")
    |> String.trim()
  end
end
