defmodule Rageg.Application do
  @moduledoc """
  OTP Application for Rageg.

  Supervises the Phoenix endpoint, PubSub, and the
  periodic stats collector that bridges Ragex/dllb
  telemetry to the LiveView dashboard.
  """

  use Application

  @impl true
  def start(_type, _args) do
    # Select the Nx/EXLA backend (CUDA when available, else CPU) before anything
    # triggers tensor compilation or model loading.
    Rageg.NxBackend.setup()

    # Load AI Keys and dynamic provider configuration
    Rageg.AIKeys.load_keys()

    # Log active storage backend configuration
    require Logger
    storage_mod = Ragex.Store.Backend.module()
    cache_mod = Metastatic.Cache.impl()

    Logger.info(
      "Active storage backend: #{inspect(storage_mod)} (AST Cache: #{inspect(cache_mod)})"
    )

    # Attach Logger-backed telemetry handlers
    Rageg.Profiles.IngestTelemetry.attach()
    Rageg.Graph.Telemetry.attach()

    children = [
      RagegWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:rageg, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Rageg.PubSub},
      # Profile manager -- CRUD, active project state, dllb ingestion
      Rageg.Profiles,
      # Periodic stats collector -- polls Ragex/dllb and broadcasts via PubSub
      Rageg.Stats,
      # Start to serve requests, typically the last entry
      RagegWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Rageg.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RagegWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
