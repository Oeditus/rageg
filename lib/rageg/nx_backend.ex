defmodule Rageg.NxBackend do
  @moduledoc """
  Selects the Nx/EXLA backend at runtime.

  Driven by `config :rageg, :nx_acceleration`:

    * `:auto` (dev/prod) - use the CUDA GPU client when a CUDA device is
      actually available, otherwise transparently fall back to the CPU
      (`:host`) client.
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

  # Probe supported platforms without building a GPU client (which could abort
  # hard when the driver is missing). A CUDA platform with at least one device
  # means the GPU is usable.
  defp cuda_available? do
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
end
