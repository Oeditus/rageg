defmodule RagegWeb.Telemetry do
  @moduledoc """
  Supervision tree for web telemetry.

  The unused `Telemetry.Metrics` scaffolding (metric definitions with no
  reporter attached) has been removed. Pipeline timings are already emitted as
  `:telemetry.span/3` events and logged by `Rageg.Profiles.IngestTelemetry` and
  `Rageg.Graph.Telemetry`. Add a reporter and metric definitions here if you
  later wire up a metrics backend (Prometheus, StatsD, etc.).
  """

  use Supervisor

  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    Supervisor.init([], strategy: :one_for_one)
  end
end
