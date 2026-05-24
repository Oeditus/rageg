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
    children = [
      RagegWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:rageg, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Rageg.PubSub},
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
