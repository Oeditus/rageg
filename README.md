# Rageg

**Phoenix LiveView GUI for [Ragex](https://github.com/Oeditus/ragex) -- Visual Code Intelligence**

Rageg is a browser-based frontend that exposes everything Ragex and dllb provide
through interactive visualizations, real-time dashboards, and developer-friendly
tools. Built with Phoenix 1.8, LiveView, DaisyUI, and D3.js.

## Features

### Phase 1 (current)

- **Real-time Dashboard** -- live stat cards for knowledge graph, embeddings,
  AI cache, AI usage, and dllb backend health. Auto-refreshes via PubSub
  every 3 seconds.
- **Application Shell** -- DaisyUI drawer sidebar with full navigation to all
  planned pages. Dark/light/system theme toggle.
- **Internationalization** -- English (default), Spanish, Catalan via Gettext.
  Switch locale with `?locale=es` or `?locale=ca`.
- **dllb Backend Explorer** -- hub page with card links to all dllb subsystems
  (actors, storage, graph, vectors, search, code-intel).

### Planned

- **Phase 2** -- Knowledge Graph Explorer (D3.js force-directed, community overlays)
- **Phase 3** -- Code Quality & Dependencies (treemaps, heatmaps, coupling matrix)
- **Phase 4** -- RAG Chat & Audit (streaming AI, tool-call visibility)
- **Phase 5** -- Visual Refactoring & Impact (CodeMirror diff, risk gauges)
- **Phase 6** -- Embedding Space (t-SNE/UMAP scatter plots)
- **Phase 7** -- dllb Backend Explorer (HNSW layers, supervision tree, keyspace browser)
- **Phase 8** -- Polish (i18n completion, keyboard shortcuts, accessibility)

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
  test/
    rageg/
      stats_test.exs       -- Stats GenServer unit tests
    rageg_web/
      live/
        dashboard_live_test.exs  -- Dashboard LiveView tests
        navigation_test.exs      -- Route and sidebar tests
      plugs/
        locale_test.exs    -- Locale plug tests
```

## License

GPL-3.0
