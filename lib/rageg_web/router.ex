defmodule RagegWeb.Router do
  @moduledoc """
  Routes for the Rageg web interface.

  All pages are LiveViews grouped by feature area:

  - `/`              -- Dashboard (real-time stats)
  - `/graph`         -- Knowledge Graph Explorer
  - `/dependencies`  -- Dependency Analysis
  - `/quality`       -- Code Quality
  - `/impact`        -- Impact Analysis
  - `/refactor`      -- Visual Refactoring
  - `/chat`          -- RAG Chat
  - `/audit`         -- Audit Report
  - `/embeddings`    -- Embedding Space
  - `/analyze`       -- Analysis Runner
  - `/dllb/*`        -- dllb Backend Explorer
  """

  use RagegWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RagegWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug RagegWeb.Plugs.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", RagegWeb do
    pipe_through :browser

    live_session :default, layout: {RagegWeb.Layouts, :app} do
      # Phase 1: Dashboard
      live "/", DashboardLive, :index

      # Phase 2: Knowledge Graph Explorer
      live "/graph", GraphLive, :index

      # Phase 3: Code Quality & Dependencies
      live "/quality", QualityLive, :index
      live "/dependencies", DependenciesLive, :index

      # Phase 4: RAG Chat & Audit
      live "/chat", ChatLive, :index
      live "/audit", AuditLive, :index

      # Phase 5: Visual Refactoring & Impact
      live "/refactor", RefactorLive, :index
      live "/impact", ImpactLive, :index

      # Phase 6: Embedding Space
      live "/embeddings", EmbeddingsLive, :index

      # Phase 7: dllb Backend Explorer
      live "/dllb", DllbLive, :index
      live "/dllb/actors", DllbLive, :actors
      live "/dllb/storage", DllbLive, :storage
      live "/dllb/graph", DllbLive, :graph
      live "/dllb/vectors", DllbLive, :vectors
      live "/dllb/search", DllbLive, :search
      live "/dllb/code-intel", DllbLive, :code_intel

      # Phase 8: Analysis Runner
      live "/analyze", AnalyzeLive, :index
    end
  end
end
