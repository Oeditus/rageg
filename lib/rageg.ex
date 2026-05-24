defmodule Rageg do
  @moduledoc """
  Rageg -- Phoenix LiveView GUI for Ragex.

  Provides a browser-based visual frontend for the Ragex code analysis
  engine and the dllb multi-model database. All state lives in Ragex
  (ETS knowledge graph, vector store, AI cache) and dllb (Rust database
  via TCP). Rageg is a pure presentation layer.

  ## Key modules

    * `Rageg.Stats` -- periodic stats collector, broadcasts via PubSub
    * `Rageg.Application` -- OTP supervision tree
    * `RagegWeb.Router` -- LiveView route definitions
    * `RagegWeb.DashboardLive` -- real-time dashboard
    * `RagegWeb.DllbLive` -- dllb backend explorer
  """
end
