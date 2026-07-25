# Rageg

**Phoenix LiveView GUI for [Ragex](https://github.com/Oeditus/ragex) -- Visual Code Intelligence**

Rageg is a browser-based frontend that exposes everything Ragex and dllb provide
through interactive visualizations, real-time dashboards, and developer-friendly
tools. Built with Phoenix 1.8, LiveView, DaisyUI, and D3.js.

## Features

### Phase 1 -- Skeleton & Dashboard

- **Real-time Dashboard** -- live stat cards for knowledge graph, embeddings,
  AI cache, AI usage, and dllb backend health. Auto-refreshes via PubSub
  every 3 seconds.
- **Application Shell** -- DaisyUI drawer sidebar with full navigation to all
  planned pages. Dark/light/system theme toggle.
- **Internationalization** -- English (default), Spanish, Catalan via Gettext.
  Switch locale with `?locale=es` or `?locale=ca`.
- **dllb Backend Explorer** -- hub page with card links to all dllb subsystems
  (actors, storage, graph, vectors, search, code-intel).

### Phase 2 -- Knowledge Graph Explorer (current)

- **D3.js Force-Directed Graph** -- interactive visualization of the code
  knowledge graph with zoom, pan, and drag.
- **Metric Coloring** -- toggle between PageRank, betweenness, degree, and
  community coloring with smooth transitions.
- **Node Sizing** -- proportional to the selected metric.
- **Edge Thickness** -- proportional to call weight (frequency).
- **Community Hulls** -- convex hull overlays when community mode is active.
- **Minimap** -- bottom-right overview with viewport indicator.
- **Module Filtering** -- real-time filter by module prefix.
- **Max Nodes Slider** -- control graph density (50--1000 nodes).
- **Node Detail Panel** -- click any node to see file, callers, callees.
- **Export** -- download as SVG or Graphviz DOT.

### Phase 3 -- Code Quality & Dependencies (current)

- **Code Quality** (`/quality`) -- tabbed interface with 6 analysis dimensions:
  - Code Smells: sortable table with type, severity, file, description
  - Security: vulnerability scanner with severity badges
  - Dead Code: unused function detection with confidence scores
  - Duplication: clone pair detection (Type I-IV) with similarity percentages
  - Complexity: cyclomatic/cognitive complexity for functions exceeding thresholds
  - Business Logic: anti-pattern detection grouped by analyzer category
- **Dependencies** (`/dependencies`) -- tabbed module-level analysis:
  - Coupling: full table of Ca/Ce/Instability per module, color-coded badges
  - Circular Deps: cycle cards with module chains
  - God Modules: high-coupling modules with warning badges
  - Unused Modules: modules with no incoming references
- Summary badges on both pages with issue counts per dimension.
- Lazy tab loading -- data fetched only when tab is activated.

### Phase 4 -- RAG Chat & Audit

- RAG Chat with streaming tokens, tool-call sidebar, provider selector
- Audit Report with full analysis pipeline, markdown viewer, export

### Phase 5 -- Visual Refactoring & Impact

- Refactoring wizard with 6 operations, dynamic parameter forms, undo
- Impact analysis with risk gauge, effort estimation, affected tests

### Phase 6 -- Embedding Space

- PCA-projected 2D scatter plot of code embeddings
- Semantic search with result highlighting, k-NN neighbor lines

### Phase 7 -- dllb Backend Explorer

- Supervision tree with actor status indicators
- Storage schema browser, graph edge types, query playground
- HNSW vector config, FTS indexes, 38 MetaAST node types

### Phase 8 -- Analysis Runner & Polish

- Analysis runner with 13 configurable analysis types
- Progress tracking with live messages
- Result cards linking to Quality/Dependencies detail pages
- All placeholder LiveViews replaced with real implementations
- 100+ tests passing across all phases

## Architecture

Rageg is a thin presentation layer. It calls Ragex public APIs directly
(same BEAM VM) rather than going through REST/MCP. LiveView processes
subscribe to PubSub topics for real-time updates.

```
Browser <-> Phoenix LiveView <-> Ragex (in-BEAM)
                             <-> Dllb Client (TCP) <-> dllb Server (Rust)
                             <-> PubSub
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for details.

## Prerequisites

- Elixir 1.18+, Erlang/OTP 27+
- Ragex (sibling directory `../ragex`)
- dllb_ex (sibling directory `../dllb_ex`)
- Optional: dllb server running for backend explorer features

## Setup

```bash
cd rageg
mix setup    # deps.get + assets.setup + assets.build
```

## Development

```bash
mix phx.server
# or
iex -S mix phx.server
```

Visit http://localhost:4000

## Tests

```bash
mix test
```

## Project Structure

```
rageg/
  lib/
    rageg/
      application.ex       -- OTP app with Stats in supervision tree
      stats.ex             -- Periodic stats collector GenServer
    rageg_web/
      router.ex            -- All LiveView routes
      components/
        layouts.ex          -- Sidebar layout, theme toggle, nav_active
        layouts/
          root.html.heex   -- HTML skeleton with theme script
          app.html.heex    -- DaisyUI drawer sidebar + topbar
        core_components.ex -- Flash, button, input, table, etc.
      live/
        dashboard_live.ex  -- Real-time dashboard with stat cards
        graph_live.ex      -- Knowledge Graph Explorer with D3 hook
        dllb_live.ex       -- dllb backend explorer (sub-page router)
        placeholder_live.ex -- Placeholder stubs for future phases
      plugs/
        locale.ex          -- i18n locale detection plug
  priv/
    gettext/
      default.pot          -- Extracted message strings
      en/LC_MESSAGES/      -- English (passthrough)
      es/LC_MESSAGES/      -- Spanish translations
      ca/LC_MESSAGES/      -- Catalan translations
  assets/
    js/
      hooks/
        graph_hook.js      -- D3.js force-directed graph visualization
  test/
    rageg/
      stats_test.exs       -- Stats GenServer unit tests
      graph_test.exs       -- Graph context module tests
    rageg_web/
      live/
        dashboard_live_test.exs  -- Dashboard LiveView tests
        graph_live_test.exs      -- Graph Explorer LiveView tests
        navigation_test.exs      -- Route and sidebar tests
      plugs/
        locale_test.exs    -- Locale plug tests
```

## License

GPL-3.0
